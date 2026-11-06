# Dream Pulse TTS — Android foundation v0.15.8

## What was removed

- The old `sherpa-onnx` / Piper Irina model downloader and its SHA-256
  installation path (which previously froze or failed at 95%).
- Native `DreamPulseVoiceService` and `DreamPulseVoiceEngine`, the
  `dream_pulse/voice` channel, and the sherpa-onnx Gradle dependency.
- Any automatic fallback to preinstalled RuVoice or system Android TTS.

**Do not confuse removing Piper *runtime* with deleting the owner's voice
identity.** The identity `irina` remains registered, but it will not speak
until a model is trained or converted for the new Dream Pulse runtime.

## What exists now

- A stable `DreamPulseVoiceBackend` Dart interface exposing five
  independent user-designed female identities:
  `irina`, `dream_ref_hello`, `dream_ref_calm`,
  `dream_ref_weather`, and `dream_ref_long`.
- Each of the four custom voice references has its own recordings and acoustic
  design. No merging into a generic speaker or assuming they share a voice.
- Kotlin `DreamPulseSileroPackStore` installs a verified local Silero
  `v5_5_ru` ZIP pack into **app-private Android storage**.
  It validates entries, limits sizes, checks SHA-256 of every model
  component, stages before replacing and can revert on failure.
- A voice settings button imports a local ZIP using the existing FilePicker.
- The text AI Core, memory, Workers/Processors/Critics and model router are
  untouched. Chat still runs with no local speech.

## Important: synthesis is NOT available yet

This milestone does **not** include trained voice weights, a native
PyTorch Lite + ExecuTorch inference backend, or finished TTS. Installing
original Silero weights only stages them. The Android channel honestly
reports `canSynthesize: false`, and the UI labels voices as pending.
It never pretends successful audio playback.

Four recordings are not directly executable speaker weights; they need
verified transcripts, clean aligned segments, and adaptation/training
while keeping each synthetic female identity separately recognizable.

## Preparing original Silero weights

The previous export/packaging tooling in
`patches/v0155/tools/build_female_base_pack.py` packages the original
RuVoice-converted Silero model components. It expects
`tts_mel.ptl`, `head.ptl`, `backbone.pte`, `accentor.ptl`,
`homo.ptl`, and `stress.bin`.
Silero model weights are **not included in the public GitHub repo**
or automatically installed in APK. Export from the author's RuVoice
development checkout, then import the resulting ZIP from voice settings.

The base weights contain the original stock Silero speaker IDs;
the UI does **not** claim these are the user's voices. Original model
license is CC BY-NC-SA 4.0, with required attribution and noncommercial
restrictions. Renaming the engine does not change that.

## Native implementation remaining

1. Build a compatible Android PyTorch Lite + ExecuTorch inference layer for
   the stored modules, avoiding collisions with the local LLM on low-RAM
   devices. Include an audio playback queue, cancellation and diagnostics.
2. Validate the Silero original weights by producing a known reference WAV
   with native inference on arm64 device; measure RAM and real-time factor.
3. Adapt/train **four separately recognizable** custom female voice models,
   and prepare a migration for Irina as a separate identity (not the stock
   Silero Irina).
4. Enable `canSynthesize` only for installed, verified checkpoints after
   actual generated speech tests.
5. If device tests pass, integrate natural turn-taking and interruptions.

## GitHub checks

CI applies `patches/v0158/patch.py`, removes native Piper through
`patches/v0158/patch_android.py`, runs Flutter analysis and tests,
builds an arm64 APK, then checks that
`libsherpa-onnx-jni.so` is absent.

**Do not install this development build if you rely on the currently working
Piper voice.** This preview version is intentionally text-only locally until
the new synthesizer is complete.
