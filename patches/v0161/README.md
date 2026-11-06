# Dream Pulse — Voice Training Lab v0.16.1 (PRIVATE audio)

This is the start of **four separate synthetic female voice adaptation tracks**
for Dream Pulse TTS. `irina` is an independent fifth author-created voice;
it is NOT included because Irina's separate source recording/checkpoint is
not provided for this experiment.

## Stage 1: genuinely fitted acoustic adapters (not voice cloning)

`tools/train_voice_adapters.py` uses original, user-owned WAV references
in a **private ZIP** and learns one regularized 24-band spectral filter per
speaker identity with PyTorch Adam. These are numeric **trained post-filters**
over an existing Silero test voice, *not fine-tuned Silero speaker weights*.
Do not claim they reproduce speaker identity, prosody, rasp, breathiness or
unseen text faithfully. The source Silero `model.ptl` is an **inference-only
TorchScript Lite export**, with frozen weights; it does not provide the
training graph and speaker embedding machinery necessary for new voices.

Original Silero: `v5_5_ru`, licensed **CC BY-NC-SA 4.0**.
Changing the engine name does not change the license.

## Voice identities (never collapse / remap)

| ID | Original private recording |
| --- | --- |
| `dream_ref_hello` | `hello.wav` — Привет |
| `dream_ref_calm` | `calm.wav` — Ты справляешься |
| `dream_ref_weather` | `weather.wav` — Как погода за окном |
| `dream_ref_long` | `long.wav` — Не спрашивай сколько |
| `irina` | **Separate identity; not trained here** |

The four examples are **intentionally engineered AI voices** with independent
timbres, pitch ranges and raspiness; do not infer they belong to one speaker.

## Running locally with private files

Requirements: Python >=3.11, numpy, scipy, soundfile, PyTorch CPU >=2.4.
Do not upload any audio to GitHub Actions or a public repository.

```bash
pip install numpy scipy soundfile torch
python patches/v0161/tools/train_voice_adapters.py \
  --references /private/Dream-Pulse-PRIVATE-Voice-Dataset-v1.zip \
  --base-wav /private/Silero-Base-Reference-For-Training.wav \
  --out /private/dream-pulse-adapters
```

The output contains four different `adapter.json` files:
`format: dream-pulse-spectral-adapter-v0`, 24 constrained EQ gain weights,
loss improvement estimates, and explicit flags `mobile_inference_ready=false`
and `is_faithful_voice_clone=false`.

## Dataset preparation

A larger private offline training toolkit includes an energy-VAD segmentation
script, a report, transcript review CSV and four **early acoustic style demos**
generated from the same phrase via original Silero base synthesis. The previews
are illustrative spectral/pitch transformations, **not neural voice clones**.

The existing references total about **260 seconds**, but draft usable
speech candidates are much less and are not yet verified. One shorter
recording has only ~11 seconds of draft speech; one 138-second recording
has continuous audio energy and requires inspection for ambience/reverb.
Missing: word-for-word transcripts, utterance boundaries, phonetic coverage,
clean recordings, held-out validation clips.

Next steps toward true distinct TTS voices:

1. Review each segment and fill a verbatim transcript. Exclude noisy and
   ambiguous material (the workflow deliberately does **not** invent text).
2. Generate/record additional phonetically diverse lines using the same
   stable voice settings for EACH of the four synthetic identities.
3. Choose a speaker-conditioned **trainable** model compatible with Android,
   or implement a trainable voice-conversion stage after Silero. Merely
   modifying frozen Silero `model.ptl` will not work.
4. Train with separate speaker ID, loss, checkpoint and validation per voice.
5. Export and benchmark portable model weights; enable the voice ID in
   Dream Pulse only after on-device unseen-text and fidelity testing.

**No private audio, trained adapters or speaker feature reports are committed
to GitHub**. Public CI tests synthesize temporary sine waves only.

## Safety

This branch makes no changes to the Flutter UI, Dream Pulse Core
(Workers/Processors/Critics), memory, LLM routing or Android runtime.
It is an offline training pipeline and cannot make the app speak these
four voices yet.
