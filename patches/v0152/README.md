# Dream Pulse Voice v0.15.2

Compatibility and on-device diagnostics.

- Audio output changed from PCM float to PCM 16-bit mono.
- Diagnostic button runs three checks in the isolated voice process:
  1. short 660 Hz speaker tone,
  2. local model load,
  3. TTS generation and sample count.
- The last completed stage is persisted in app-private storage so a native
  crash or timeout can still be identified after the voice process exits.
- Voice model remains Piper Irina through sherpa-onnx; Dream · Zoey-style is
  the app-side tuning profile, not copied Character.AI weights.
