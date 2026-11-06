"""Install four actual learned author-voice *timbre* weights in Dream Pulse.

Run AFTER patches/v0159/patch_android.py.
Does NOT modify AI Core, speech model neural weights or private references.
"""
from pathlib import Path
import shutil

root = Path("android/app/src/main")
native = root / "kotlin/com/dreampulse/assistant"
styles = root / "assets/dream_pulse_tts/styles"
styles.mkdir(parents=True, exist_ok=True)

ids = [
    "dream_ref_hello",
    "dream_ref_calm",
    "dream_ref_weather",
    "dream_ref_long",
]
for voice in ids:
    shutil.copyfile(
        "patches/v0162/voice_weights/" + voice + ".json",
        styles / (voice + ".json"),
    )
shutil.copyfile(
    "patches/v0162/android/DreamPulseTrainedTimbre.kt",
    native / "DreamPulseTrainedTimbre.kt",
)


def once(path, old, new):
    src = path.read_text(encoding="utf-8")
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f"{path}: expected one anchor, got {n}: {old[:90]!r}")
    path.write_text(src.replace(old, new, 1), encoding="utf-8")


synth = native / "DreamPulseSileroLiteSynth.kt"
once(
    synth,
    '    fun preview(text: String = "прив+ет, м+ир."): Int {',
    '    fun preview(text: String = "прив+ет, м+ир.", styleId: String? = null): Int {',
)
once(
    synth,
    """        playPcm(pcm, token)
        return output.size""",
    """        // Technical reference style only: Silero's stock source speaker
        // is filtered with independently learned timbre weights. It is NOT
        // a trained model of the owner's authored speaker identity.
        val colored = if (styleId == null) pcm
            else DreamPulseTrainedTimbre(context).apply(styleId, pcm)
        if (token != generation.get()) throw InterruptedException("Cancelled")
        playPcm(colored, token)
        return output.size""",
)

service = native / "DreamPulseSileroPreviewService.kt"
once(
    service,
    """                inFlight.incrementAndGet()
                executor.execute {""",
    """                val styleId = intent.getStringExtra(EXTRA_STYLE_ID)
                inFlight.incrementAndGet()
                executor.execute {""",
)
once(
    service,
    """                        val n = synth.preview(phrase)
                        callback?.send(RESULT_OK, Bundle().apply {
                            putInt("samples", n)
                            putString("message", "Silero Lite PCM 24 kHz generated")
                        })""",
    """                        val n = synth.preview(phrase, styleId)
                        callback?.send(RESULT_OK, Bundle().apply {
                            putInt("samples", n)
                            putString(
                                "message",
                                if (styleId == null) {
                                    "Silero Lite PCM 24 kHz generated"
                                } else {
                                    "Silero + experimental learned timbre $styleId"
                                },
                            )
                        })""",
)
once(
    service,
    '        const val EXTRA_TEXT = "phrase"',
    '        const val EXTRA_TEXT = "phrase"\n        const val EXTRA_STYLE_ID = "style_id"',
)
main = native / "MainActivity.kt"
once(
    main,
    '                "previewBase" -> {',
    '                "previewBase", "previewStyle" -> {',
)
once(
    main,
    """                    val phrase = call.argument<String>("text")
                        ?.take(180) ?: "прив+ет, м+ир."
                    val receiver""",
    """                    val phrase = call.argument<String>("text")
                        ?.take(180) ?: "прив+ет, м+ир."
                    val styleId = if (call.method == "previewStyle") {
                        call.argument<String>("voice")
                    } else null
                    if (call.method == "previewStyle" && styleId.isNullOrBlank()) {
                        result.error("VOICE_ID_REQUIRED", "Select an author voice", null)
                        return@setMethodCallHandler
                    }
                    val receiver""",
)
once(
    main,
    """                                putExtra(DreamPulseSileroPreviewService.EXTRA_TEXT, phrase)
                                putExtra(DreamPulseSileroPreviewService.EXTRA_RECEIVER, receiver)""",
    """                                putExtra(DreamPulseSileroPreviewService.EXTRA_TEXT, phrase)
                                if (styleId != null) {
                                    putExtra(
                                        DreamPulseSileroPreviewService.EXTRA_STYLE_ID,
                                        styleId,
                                    )
                                }
                                putExtra(DreamPulseSileroPreviewService.EXTRA_RECEIVER, receiver)""",
)
print("Four distinct learned timbre weight packs are installed in Android assets.")
