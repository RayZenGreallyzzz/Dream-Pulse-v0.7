#!/usr/bin/env python3
"""Package EXISTING RuVoice-exported Silero v5_5_ru model weights for Dream Pulse.

No model files are committed to GitHub. Run after RuVoice's normal export
pipeline. This packages only a verified local copy of the original weights
and metadata. It does NOT make the private WAV voices synthesize speech.
The APK does not load this pack until a separate native runtime is built.
"""
import argparse
import hashlib
import json
import pathlib
import zipfile

MODEL_FILES = {
    "tts_mel.ptl": "app/src/full/assets/silero/tts_mel.ptl",
    "backbone.pte": "app/src/full/assets/silero/backbone.pte",
    "head.ptl": "app/src/full/assets/silero/head.ptl",
    "accentor.ptl": "app/src/main/assets/silero/accentor.ptl",
    "homo.ptl": "app/src/main/assets/silero/homo.ptl",
}
INTERNAL_FEMALE_SILERO_SPEAKERS = ["baya", "kseniya", "xenia"]


def digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def build(source: pathlib.Path, stress: pathlib.Path, output: pathlib.Path) -> dict:
    files = {name: source / subpath for name, subpath in MODEL_FILES.items()}
    files["stress.bin"] = stress
    missing = [str(path) for path in files.values() if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise FileNotFoundError("First run RuVoice model export; missing: " + ", ".join(missing))
    if output.exists():
        raise FileExistsError(f"Will not overwrite existing pack: {output}")
    if output.parent:
        output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "format": "dream-pulse-silero-base-v1",
        "model_id": "v5_5_ru",
        "model_origin": "https://github.com/snakers4/silero-models",
        "export_pipeline": "RayZenGreallyzzz/ruvoice",
        "license": "CC BY-NC-SA 4.0",
        "non_commercial_only": True,
        "speaker_filter": INTERNAL_FEMALE_SILERO_SPEAKERS,
        "ui_voices": [],
        "user_recordings_trained": False,
        "native_runtime_embedded": False,
        "files": {
            filename: {
                "sha256": digest(path),
                "bytes": path.stat().st_size,
            }
            for filename, path in sorted(files.items())
        },
    }
    try:
        with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_STORED) as package:
            for filename, path in sorted(files.items()):
                package.write(path, arcname="silero/" + filename)
            package.writestr(
                "silero/manifest.json",
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            )
    except Exception:
        output.unlink(missing_ok=True)
        raise
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ruvoice-checkout", type=pathlib.Path, required=True)
    parser.add_argument("--stress-bin", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    manifest = build(args.ruvoice_checkout, args.stress_bin, args.output)
    print(json.dumps({
        "output": str(args.output),
        "voices_visible": manifest["ui_voices"],
        "female_silero_speakers_internal": manifest["speaker_filter"],
        "file_count": len(manifest["files"]),
        "native_runtime_embedded": False,
        "custom_voices_trained": False,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
