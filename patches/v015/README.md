# Dream Pulse Voice Core v0.15

This patch replaces the experimental PyTorch Lite + ExecuTorch Silero runtime
with a private local sherpa-onnx runtime in the isolated Android `:voice`
process.

## Runtime

- sherpa-onnx Android AAR: v1.13.8 (Apache-2.0)
- Initial local Russian model: Piper `ru_RU-irina-medium`
- Model pack is downloaded directly from the official sherpa-onnx TTS release
  and verified with SHA-256 before extraction.
- Model pack SHA-256:
  `1fc0f54e5e084fe287c07909f2f6e0ba6d857864cf800e3ab80286a4e8233008`

## Local profiles

- `Dream · Zoey-style`: Dream Pulse tuning profile based on the user's
  reference characteristics. It is not the Character.AI Zoey model and does
  not copy Character.AI weights.
- `Irina · base`: neutral baseline for comparing the underlying local model.

The downloaded model is stored under app-private files and survives APK
upgrades.
