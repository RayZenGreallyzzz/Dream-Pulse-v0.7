#!/usr/bin/env python3
"""Export the ORIGINAL licensed Silero v5_5_ru model as full PyTorch Lite.

Uses the same upstream v5_5_ru.pt package as RuVoice, but a SINGLE
TorchScript Lite module replaces the split PyTorch+ExecuTorch pipeline.

The exported reference pack is a DEVELOPMENT TEST voice (stock female
speaker Baya), NOT any of the five user-designed Dream Pulse voices.
This script is run locally, outside the Android APK build; do not commit
source model weights or generated packs to public GitHub.

Setup in RuVoice's existing Torch environment:
  pip install -r tools/requirements.txt
  curl -L -o tools/v5_5_ru.pt \
      https://models.silero.ai/models/tts/ru/v5_5_ru.pt
  python3 patches/v0159/tools/export_full_lite.py \
      --source-model /private/ruvoice/tools/v5_5_ru.pt \
      --output /private/dream-pulse-silero-full-lite.zip
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import zipfile

FORMAT = "dream-pulse-silero-full-lite-v1"
MODEL_ID = "v5_5_ru"
MODEL_ORIGIN = "https://models.silero.ai/models/tts/ru/v5_5_ru.pt"
LICENSE = "CC BY-NC-SA 4.0"
FEMALE = ("baya", "kseniya", "xenia")
FILES = ("model.ptl", "symbols.json")


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pack_files(directory: Path, output: Path) -> dict:
    """Package verified local artifacts; does not generate new model weights."""
    if output.exists():
        raise FileExistsError(f"Existing model pack will not be overwritten: {output}")
    paths = {name: directory / name for name in FILES}
    for name, path in paths.items():
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(f"Missing exported Silero module {name}")
    symbols = json.loads(paths["symbols.json"].read_text(encoding="utf-8"))
    required = ("symbol_to_id", "sos", "eos", "speakers")
    if not all(key in symbols for key in required):
        raise ValueError("Silero symbols.json missing required metadata")
    if not all(name in symbols["speakers"] for name in FEMALE):
        raise ValueError("Source model lacks expected female test speakers")

    manifest = {
        "format": FORMAT,
        "model_id": MODEL_ID,
        "model_origin": MODEL_ORIGIN,
        "license": LICENSE,
        "non_commercial_only": True,
        "model_variant": "torchscript_lite_full",
        "female_test_speakers": list(FEMALE),
        "public_voice_ids": [],  # stock test voice is NOT user's voice
        "trained_user_voices": [],
        "silero_backend_test_only": True,
        "files": {
            name: {
                "bytes": path.stat().st_size,
                "sha256": file_hash(path),
            } for name, path in sorted(paths.items())
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_STORED) as pack:
        for name, path in sorted(paths.items()):
            pack.write(path, f"silero/{name}")
        pack.writestr(
            "silero/manifest.json",
            json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        )
    return manifest


def export(source_model: Path, out_dir: Path) -> None:
    import torch
    from torch.jit.mobile import _load_for_lite_interpreter

    model = torch.package.PackageImporter(str(source_model)) \
        .load_pickle("tts_models", "model")
    assert len(model.packages) == 1, "Only a single Silero v5_5_ru package is supported"
    package = model.packages[0]
    module = package.models[0]
    speakers = package.speaker_to_ids[0]
    assert all(name in speakers for name in FEMALE)
    assert "baya" in speakers

    out_dir.mkdir(parents=True, exist_ok=True)
    # Unlike RuVoice's speed-optimized split, we do NOT cut the vocoder out.
    # The original graph and its weights remain in a single mobile model.
    module.eval()
    frozen = torch.jit.freeze(module)
    module_path = out_dir / "model.ptl"
    frozen._save_for_lite_interpreter(str(module_path))

    meta = {
        "symbols": package.symbols,
        "symbol_to_id": package.symbol_to_id,
        "sos": package.sos_token,
        "eos": package.eos_token,
        "speakers": {name: int(speakers[name]) for name in FEMALE},
        "sample_rate": 24000,
        "type_ids": True,
    }
    (out_dir / "symbols.json").write_text(
        json.dumps(meta, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    # Numerical regression: mobile output must match the original full model.
    # RuVoice's existing prototype used this same reference phrase.
    seq, _ = package.preprocess_tacotron("прив+ет, м+ир.")
    seq = seq.unsqueeze(0)
    n = seq.shape[1]
    args = (
        seq,
        torch.tensor([speakers["baya"]], dtype=torch.long),
        24000,
        None,
        torch.ones(1, n),
        torch.ones(1, n),
        None,
        None,
        "cpu",
        -1,
        False,
        torch.zeros(1, n, dtype=torch.long),
        None,
    )
    with torch.no_grad():
        native_reference = module(*args)[0]
        mobile_audio = _load_for_lite_interpreter(str(module_path))(*args)[0]
    difference = (native_reference - mobile_audio).abs().max().item()
    assert difference < 1e-4, f"TorchScript-Lite speech mismatch: {difference}"
    assert mobile_audio.numel() > 2400, "Export produced empty audio"
    print(f"verified full Lite export: max absolute PCM error {difference:.6g}")
    print(f"model bytes: {module_path.stat().st_size}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-model", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not args.source_model.is_file():
        parser.error("Missing original v5_5_ru.pt model")
    with tempfile.TemporaryDirectory(prefix="dream-silero-") as tmp:
        directory = Path(tmp)
        export(args.source_model, directory)
        manifest = pack_files(directory, args.output)
    print(json.dumps({
        "package": str(args.output),
        "bytes": args.output.stat().st_size,
        "license": manifest["license"],
        "user_voices_trained": False,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
