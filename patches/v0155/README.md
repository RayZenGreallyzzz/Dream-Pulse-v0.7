# Dream Pulse TTS · female-only embedded Silero roadmap (v0.15.5)

This is the correction to the v0.15.4 experimental RuVoice bridge.
**The target is an internal Android Dream Pulse TTS engine**, with original
Silero weights and only the female voices specified by the project owner.

## Voice policy (not a misleading demo)

| Voice / reference | Current runtime | State |
| --- | --- | --- |
| Irina | Existing Piper / sherpa-onnx | **Available today** |
| 'Привет' WAV | Future custom female TTS | **Recording only** |
| 'Ты справляешься' WAV | Future custom female TTS | **Recording only** |
| 'Как погода за окном' WAV | Future custom female TTS | **Recording only** |
| 'Не спрашивай сколько' WAV | Future custom female TTS | **Recording only** |

The four WAV clips may represent one person's voice with different speaking
styles rather than four separate speaker identities. Do not assume they are
four trainable voices without speaker assessment and careful transcriptions.
No recording is uploaded to public GitHub. They are private training inputs.

Silero `v5_5_ru` has *existing* speaker IDs for `baya`, `kseniya`,
`xenia`, `aidar`, and `eugene`. Its pre-trained speaker embeddings do
**NOT** produce the sound of the supplied recordings. We must train or
adapt a compatible speaker representation and verify pronunciation, timbre
and naturalness before enabling each private voice.

## Native model and original weights

The existing RuVoice repository provides a tested conversion pipeline:

- Original `v5_5_ru.pt` weights, fetched from Silero.
- `tts_mel.ptl` and `head.ptl` (PyTorch Lite).
- `backbone.pte` (ExecuTorch XNNPACK).
- `accentor.ptl`, `homo.ptl`, `stress.bin` for preprocessing.

The model files **are not in the public RuVoice repository** and therefore
are not secretly embedded in the existing Dream Pulse APK. The script
`tools/build_female_base_pack.py` verifies the local exported files,
records SHA-256 hashes and creates a pack for a later native build:

```sh
# Follow the existing RuVoice README export procedure FIRST.
python3 patches/v0155/tools/build_female_base_pack.py \
  --ruvoice-checkout /private/path/to/ruvoice \
  --stress-bin /private/path/to/ruvoice/app/build/generated/stressBin/.../stress.bin \
  --output /private/dream-pulse-silero-base.zip
```

The stress.bin path depends on the RuVoice Gradle build output. This
packager **does not** convert weights, install Android inference libraries,
or make a working TTS in Dream Pulse on its own.

For now the pack metadata allows only the *existing* Silero female
speaker IDs internally for technical smoke tests. Those stock speakers
are **not shown** as finished Dream Pulse voices. Male model speaker
entries remain in the original weight tensors; simply hiding their IDs
is sufficient to make the **UI female-only**, but is not physical pruning
of the weights.

## Remaining work to ship a real embedded model

1. Export / verify the original Silero weights with RuVoice tools and
   generate model assets (not part of this GitHub commit).
2. Build in-process or isolated-process Android PyTorch Lite + ExecuTorch
   inference. Avoid simultaneous residency of local LLM and both TTS models.
3. Reuse normalization, stress, and prosody handling from RuVoice under
   the appropriate code license. Validate pronunciation with regression WAVs.
4. Verify model preloading, stopping speech, PCM16 audio output and memory
   pressure on actual Android ARM64 devices.
5. Prepare verified transcripts and clean utterance segmentation from the
   private recordings. Train or adapt compatible voice model weights.
6. Enable a voice ID only when that checkpoint is actually present and
   synthesized audio has passed quality tests.
7. **Only then** bundle approved model files in a Dream Pulse release APK.

## Licensing

The Silero upstream repository has CC BY-NC-SA 4.0 for `v5_5_ru`.
The project can create a custom engine and derivative models for
**non-commercial** use subject to license and attribution obligations.
Changing names or only keeping the female speaker IDs does not remove
the original license. A different Silero `v5_cis_base_nostress` base
is MIT, but its pronunciation and compatibility differ; it is **not**
silently substituted for the requested `v5_5_ru` weights.

Original Silero: https://github.com/snakers4/silero-models
RuVoice code: https://github.com/RayZenGreallyzzz/ruvoice

**The app remains Android-first and Dream Pulse Core remains unchanged.**
