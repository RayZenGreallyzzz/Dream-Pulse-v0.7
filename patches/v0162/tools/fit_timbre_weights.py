#!/usr/bin/env python3
"""Reproducible four-voice, PyTorch-trained PCM timbre adapters.

Reference files stay PRIVATE. The public GitHub repository stores only small
learned FIR filter weights, NOT source audio. This is explicitly not Silero
fine-tuning or faithful speaker cloning: the same stock female Silero source
voice is timbre-colored differently for each author-defined identity.

pip install numpy scipy soundfile torch
python patches/v0162/tools/fit_timbre_weights.py \
  --references /private/Dream-Pulse-PRIVATE-Voice-Dataset-v1.zip \
  --base-wav /private/silero_first_base_hello.wav \
  --output /private/trained
"""
import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal
import torch

SR = 24000
N_TAPS = 257
ROOT = "dream-voice-references/"
FILES = {
    "dream_ref_hello": "hello.wav",
    "dream_ref_calm": "calm.wav",
    "dream_ref_weather": "weather.wav",
    "dream_ref_long": "long.wav",
}
BANDS = np.geomspace(95, 9400, 48)


def load_refs(path: Path):
    refs = {}
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Damaged reference archive")
        manifest = json.loads(archive.read(ROOT + "manifest.json"))
        known = {v["id"]: v for v in manifest["voices"]}
        if set(known) != set(FILES):
            raise ValueError("Private data must contain all four voice IDs")
        for voice, filename in FILES.items():
            if known[voice]["file"] != filename:
                raise ValueError("Voice ID mapping mismatch")
            raw = archive.read(ROOT + filename)
            if hashlib.sha256(raw).hexdigest() != known[voice]["sha256"]:
                raise ValueError("Reference SHA-256 mismatch")
            samples, rate = sf.read(io.BytesIO(raw), dtype="float32")
            if rate != SR or samples.ndim != 1 or not np.isfinite(samples).all():
                raise ValueError("Each reference must be 24kHz mono, finite")
            refs[voice] = samples
    return refs


def spectra(wave, split=0):
    hp = signal.butter(2, 70, "highpass", fs=SR, output="sos")
    wave = signal.sosfilt(hp, wave.astype(np.float64))
    freq, _, spec = signal.stft(
        wave, fs=SR, nperseg=1024, noverlap=768,
        boundary=None, padded=False,
    )
    amp = np.abs(spec)
    energy = np.sqrt(np.maximum((amp ** 2).mean(axis=0), 1e-14))
    active = energy > max(np.quantile(energy, 0.7) * 0.22, 3e-5)
    positions = np.flatnonzero(active)
    if len(positions) < 20:
        raise ValueError("Insufficient voice activity")
    if split == 1:
        positions = positions[positions % 5 != 0]
    elif split == 2:
        positions = positions[positions % 5 == 0]
    if len(positions) < 5:
        raise ValueError("Insufficient held-out voice data")
    amp = amp[:, positions] / np.maximum(energy[positions][None, :], 1e-7)
    power_db = np.log10(np.maximum(amp, 1e-5)) * 20
    features = []
    for hz in BANDS:
        near = (freq >= hz / 1.14) & (freq <= hz * 1.14)
        if not near.any():
            near[np.argmin(np.abs(freq - hz))] = True
        features.append(float(np.median(power_db[near, :].mean(axis=0))))
    features = np.array(features, dtype=np.float64)
    return features - features.mean()


def fit(base, target, voice_id, epochs=420):
    source = spectra(base)
    reference_train = spectra(target, 1)
    reference_heldout = spectra(target, 2)
    desired = np.clip(reference_train - source, -10, 10)
    torch.manual_seed(76)
    coefficients = torch.nn.Parameter(
        torch.zeros(len(BANDS), dtype=torch.float32),
    )
    optimizer = torch.optim.Adam([coefficients], lr=0.08)
    desired_t = torch.as_tensor(desired, dtype=torch.float32)
    for _ in range(epochs):
        optimizer.zero_grad()
        curved = coefficients[2:] - 2 * coefficients[1:-1] + coefficients[:-2]
        loss = (
            (coefficients - desired_t).square().mean()
            + 0.12 * coefficients.square().mean()
            + 0.45 * curved.square().mean()
        )
        loss.backward()
        optimizer.step()
        with torch.no_grad():
            coefficients.clamp_(-6.0, 6.0)

    gain = coefficients.detach().cpu().numpy().astype(np.float64)
    freq = np.r_[0.0, BANDS, SR / 2.0]
    response = np.r_[0.0, gain, 0.0]
    taps = signal.firwin2(
        N_TAPS, freq, 10 ** (response / 20),
        fs=SR, window="hann",
    )
    _, H = signal.freqz(taps, worN=4096, fs=SR)
    estimated = np.interp(
        BANDS, np.linspace(0, SR / 2, len(H)),
        20 * np.log10(np.maximum(abs(H), 1e-9)),
    )
    before = float(np.sqrt(np.mean((reference_heldout - source) ** 2)))
    after = float(np.sqrt(np.mean(
        (reference_heldout - source - estimated) ** 2,
    )))
    if after >= before:
        for scale in (0.75, 0.5, 0.25):
            candidate = signal.firwin2(
                N_TAPS, freq, 10 ** (response * scale / 20),
                fs=SR, window="hann",
            )
            _, h = signal.freqz(candidate, worN=4096, fs=SR)
            candidate_gain = np.interp(
                BANDS, np.linspace(0, SR / 2, len(h)),
                20 * np.log10(np.maximum(abs(h), 1e-9)),
            )
            error = float(np.sqrt(np.mean(
                (reference_heldout - source - candidate_gain) ** 2,
            )))
            if error < after:
                taps, gain, after = candidate, gain * scale, error

    if not np.isfinite(taps).all():
        raise ValueError("Nonfinite fitted FIR model weights")
    # Store 129 weights; symmetry reconstructs the complete 257-tap FIR.
    center_out = np.array(taps[N_TAPS // 2::-1]).round(8).tolist()
    return {
        "format": "dream-pulse-timbre-fir-v1",
        "voice_id": voice_id,
        "source_model": "silero-v5_5_ru",
        "sample_rate": SR,
        "fir_center_to_edge": center_out,
        "train_algorithm": "pytorch_adam_log_spectrum_match",
        "train_epochs": epochs,
        "heldout_spectral_distance_before_db": round(before, 3),
        "heldout_spectral_distance_after_db": round(after, 3),
        "is_author_voice_clone": False,
        "silero_neural_weights_changed": False,
        "user_voice_recording_included": False,
        "requires_silero_full_lite_pack": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", required=True, type=Path)
    parser.add_argument("--base-wav", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    data = load_refs(args.references)
    base, rate = sf.read(args.base_wav, dtype="float32")
    if rate != SR or base.ndim != 1 or len(base) < SR // 2:
        raise ValueError("Need stock Silero PCM 24kHz mono reference WAV")
    args.output.mkdir(parents=True, exist_ok=True)
    summary = {}
    for voice, target in data.items():
        weights = fit(base, target, voice)
        (args.output / (voice + ".json")).write_text(
            json.dumps(weights, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        summary[voice] = {
            "error_before": weights["heldout_spectral_distance_before_db"],
            "error_after": weights["heldout_spectral_distance_after_db"],
        }
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
