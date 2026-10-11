# Dream Pulse Voice v0.15.1

Runtime reliability pass for the first sherpa-onnx build.

Changes:

- Uses sherpa-onnx's streaming generation callback directly.
- Streams PCM float chunks straight into Android AudioTrack, matching the
  official sherpa-onnx Android example.
- Uses one CPU inference thread for the first compatibility build.
- Removes the custom full-buffer resampling path from the critical audio route.
- Removes the explicit process kill after every utterance.
- Persists precise stages:
  `native_load -> model_create -> model_loaded -> audio_track_ready ->
  tts_stream -> audio_first_chunk -> tts_generated -> audio_drain -> done`.

Pitch/timbre controls remain in the UI for the later voice-shaping pass, but
v0.15.1 prioritizes a known-good raw TTS path first.
