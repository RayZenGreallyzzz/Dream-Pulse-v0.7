# Dream Pulse Voice v0.15.4 — Android groundwork

This branch is deliberately **not** a replacement for Dream Pulse Core.

## What actually works after installation

- The existing **Piper Irina (Sherpa-ONNX)** local TTS and Zoey-style
  performance profile are untouched.
- If the separate **RuVoice** app
  (`ru.kost.ruvoice`) is installed and reports an Android TTS engine,
  the voice selector exposes **Baya, Kseniya, Xenia** and routes
  synthesis through the standard Android TTS interface. This first bridge
  is useful for testing pronunciation and voice selection but is NOT an
  embedded Silero model: the other application is still required.
- Voice selection is persisted for the installed RuVoice backend;
  stop/interrupt uses the same SpeechController flow.
- Four PRIVATE user WAV references are listed with **explicit untrained**
  labels. They cannot synthesize arbitrary text yet. Their audio is not in
  public GitHub or the APK. A separate private ZIP contains 24kHz mono
  PCM16 conversions for future supervised training after transcript review.
- Flutter analyzer lint cleanup: obsolete speech_to_text parameters, stale
  imports, opacity deprecations; regression tests added.

## What was learned from RayZenGreallyzzz/ruvoice

RuVoice is an elaborate Android application, not a single Silero model.
Important components:

1. `app/src/main/java/ru/kost/ruvoice/SileroTtsService.kt`
   — Android `TextToSpeechService` and text-to-audio orchestration.
2. `SileroModels.kt`
   — model management: PyTorch Lite mel/head; ExecuTorch XNNPACK vocoder
   backbone; stress modules, load/unload and memory/CPU behavior.
3. `text/Normalizer.kt`
   — numbers, dates, amounts, abbreviations, Cyrillic transcription,
   morphological normalization and spoken forms.
4. `Pack.kt`
   — transactional ZIP-based voice model installation, versioned pack
   metadata and stable speaker identifiers.
5. `Speaker.kt`
   — voice and pack routing, listing Baya/Kseniya/Xenia in the current
   female-only RuVoice build.
6. `tools/export_silero.py`, `tools/vocoder_et.py`
   — offline conversion and verification of model assets.

The Silero `v5_5_ru` model is described in the RuVoice README as
**CC BY-NC-SA 4.0** (non-commercial and share-alike restrictions). Verify
license details, attribution, model weights, and commercial-distribution
plans before shipping embedded model binaries. RuVoice generated assets
are excluded from its GitHub repository, so a standalone Dream Pulse APK
does not magically contain them. The voice examples do not make Silero
speak in those new voices without model adaptation/training.

## Proposed safe embedding path (NOT implemented in 0.15.4)

1. Resolve licensing of software and `v5_5_ru` model weights.
2. Extract the smallest needed RU text normalization + stress functions
   from RuVoice, with their test vectors.
3. Isolate PyTorch-Lite + ExecuTorch inference behind an Android native
   `DreamVoiceEngine` interface that can load a verified voice pack
   from app assets and run in an isolated low-memory process.
4. Profile cold-start time and peak RAM alongside local LLM on the real
   4GB Android device. Never load two full TTS runtimes simultaneously.
5. Move the verified model pack into the Dream Pulse APK (if license
   permits). Only then remove the external RuVoice application dependency.
6. Train or fine-tune a **compatible** mobile TTS model for the user's
   voice recordings after clean segmentation and verified transcripts.
   Import model weights only; WAV examples stay private.

## Build / testing

The main Android GitHub Actions workflow applies patches v0.8–v0.15.3,
then v0.15.4. Runs existing Core regression tests and a catalog regression
suite, followed by an ARM64 APK build. In-app voice playback and memory
behavior still need physical Android device testing.

## Source repository

RuVoice: https://github.com/RayZenGreallyzzz/ruvoice

Dream Pulse: https://github.com/RayZenGreallyzzz/Dream-Pulse-v0.7
