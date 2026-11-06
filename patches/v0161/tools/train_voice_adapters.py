#!/usr/bin/env python3
"""Dream Pulse voice training lab — public code, PRIVATE training audio.

This is an *acoustic adapter* baseline, NOT neural speaker cloning and NOT
fine-tuning of Silero. It learns 24 equalization gains per independently
designed author voice from unpaired recordings, with regularization.
Four speaker IDs stay separate. Original model weights are not modified.

Usage:
  python patches/v0161/tools/train_voice_adapters.py \
    --references /private/Dream-Pulse-PRIVATE-Voice-Dataset-v1.zip \
    --base-wav /private/Silero-Base-Reference-For-Training.wav \
    --out /private/adapters
"""
import argparse
import hashlib
import io
import json
import math
import zipfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR = 24000
PREFIX = "dream-voice-references/"
SPEAKERS = {
    "dream_ref_hello": "hello.wav",
    "dream_ref_calm": "calm.wav",
    "dream_ref_weather": "weather.wav",
    "dream_ref_long": "long.wav",
}
BANDS = np.geomspace(85.0, 9000.0, 24)


def read_references(path):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError("Invalid reference ZIP")
        manifest = json.loads(archive.read(PREFIX + "manifest.json"))
        declared = {item["id"]: item for item in manifest["voices"]}
        if set(declared) != set(SPEAKERS):
            raise ValueError("Expected exactly four independent speaker IDs")
        result = {}
        for speaker, filename in SPEAKERS.items():
            item = declared[speaker]
            if item["file"] != filename:
                raise ValueError("Voice ID-to-recording mapping mismatch")
            raw = archive.read(PREFIX + filename)
            if hashlib.sha256(raw).hexdigest() != item["sha256"]:
                raise ValueError("Reference SHA-256 mismatch for " + speaker)
            audio, rate = sf.read(io.BytesIO(raw), dtype="float32")
            if rate != SR or audio.ndim != 1 or not np.isfinite(audio).all():
                raise ValueError("Each reference must be finite 24kHz mono PCM")
            result[speaker] = audio
    return result


def spectrum(data):
    sos = signal.butter(2, 65.0, "highpass", fs=SR, output="sos")
    filtered = signal.sosfilt(sos, data.astype(np.float64))
    f, _, stft = signal.stft(
        filtered, fs=SR, nperseg=1024, noverlap=768,
        padded=False, boundary=None
    )
    magnitude = abs(stft)
    energy = np.sqrt(np.maximum(np.mean(magnitude**2, axis=0), 1e-12))
    active = energy > max(float(np.quantile(energy, 0.75)) * 0.25, 4e-5)
    if active.sum() < 20:
        raise ValueError("Too little voice activity: review audio source")
    magnitude = magnitude[:, active] / np.maximum(energy[None, active], 1e-7)
    log_spectrum = np.log(np.maximum(magnitude, 1e-5))
    features = []
    for hz in BANDS:
        use = (f >= hz/1.12) & (f <= hz*1.12)
        if not np.any(use):
            use[np.argmin(abs(f - hz))] = True
        features.append(float(np.median(np.mean(log_spectrum[use], axis=0))))
    return np.asarray(features, np.float32)


def train_one(base, target, speaker):
    import torch
    base_spectrum = spectrum(base)
    target_spectrum = spectrum(target)
    delta_db = torch.tensor(
        (target_spectrum - base_spectrum) * (20.0 / math.log(10.0)),
        dtype=torch.float32
    )
    eq = torch.nn.Parameter(torch.zeros(len(BANDS)))
    optimizer = torch.optim.Adam([eq], lr=0.075)
    for _ in range(250):
        optimizer.zero_grad()
        difference = eq - delta_db
        curvature = eq[2:] - 2*eq[1:-1] + eq[:-2]
        loss = (difference**2).mean() + 0.15*(eq**2).mean() + 0.6*(curvature**2).mean()
        loss.backward()
        optimizer.step()
        with torch.no_grad():
            eq.clamp_(-6, 6)
    with torch.no_grad():
        before = float((delta_db**2).mean().sqrt())
        after = float(((eq - delta_db)**2).mean().sqrt())
        gains = [round(float(v), 3) for v in eq]
    return {
        "format": "dream-pulse-spectral-adapter-v0",
        "voice_id": speaker,
        "base_model": "silero-v5_5_ru",
        "type": "learned_24_band_spectral_tone_adapter",
        "band_centers_hz": [round(float(v), 2) for v in BANDS],
        "trained_gain_db": gains,
        "spectral_error_before_db": round(before, 3),
        "spectral_error_after_db": round(after, 3),
        "silero_weights_modified": False,
        "is_faithful_voice_clone": False,
        "mobile_inference_ready": False,
        "needs_verified_transcripts": True,
        "privacy": "private-user-voice-artifact-do-not-commit",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--references", required=True, type=Path)
    parser.add_argument("--base-wav", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    references = read_references(args.references)
    base, sample_rate = sf.read(args.base_wav, dtype="float32")
    if sample_rate != SR or base.ndim != 1 or len(base) < SR//2:
        raise ValueError("Silero source must be a mono 24kHz WAV")
    args.out.mkdir(parents=True, exist_ok=True)
    status = {}
    for speaker, recording in references.items():
        result = train_one(base, recording, speaker)
        speaker_dir = args.out / speaker
        speaker_dir.mkdir(exist_ok=True)
        (speaker_dir / "adapter.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        status[speaker] = {
            "loss_before_db": result["spectral_error_before_db"],
            "loss_after_db": result["spectral_error_after_db"],
            "ready_for_android": False,
        }
    print(json.dumps(status, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
