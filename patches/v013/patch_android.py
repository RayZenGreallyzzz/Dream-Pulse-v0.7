from pathlib import Path
import re

engine = Path('android/app/src/main/kotlin/com/dreampulse/assistant/DreamPulseVoiceEngine.kt')
s = engine.read_text()

s = re.sub(
    r'''    fun modelPresent\(\): Boolean = try \{.*?    \} catch \(_: Throwable\) \{\n        false\n    \}''',
    '''    fun voiceDir(): File = File(context.filesDir, "dream-pulse-voice")

    fun modelPresent(): Boolean {
        val dir = voiceDir()
        return listOf("tts_mel.ptl", "head.ptl", "accentor.ptl", "backbone.pte")
            .all { File(dir, it).let { f -> f.isFile && f.length() > 1024L } }
    }''',
    s,
    count=1,
    flags=re.S,
)

old = '''        LitePyTorchAndroid.setNumThreads(threads)
        accentor = LiteModuleLoader.loadModuleFromAsset(
            context.assets,
            "$MODEL_DIR/accentor.ptl",
        )
        mel = LiteModuleLoader.loadModuleFromAsset(
            context.assets,
            "$MODEL_DIR/tts_mel.ptl",
        )
        head = LiteModuleLoader.loadModuleFromAsset(
            context.assets,
            "$MODEL_DIR/head.ptl",
        )

        val backboneFile = File(context.filesDir, "dream-pulse-voice/backbone-v5_5_ru.pte")
        if (!backboneFile.exists() || backboneFile.length() < 1024L) {
            backboneFile.parentFile?.mkdirs()
            context.assets.open("$MODEL_DIR/backbone.pte").use { input ->
                backboneFile.outputStream().use { output -> input.copyTo(output) }
            }
        }

        backbone = org.pytorch.executorch.Module.load(
            backboneFile.absolutePath,
            org.pytorch.executorch.Module.LOAD_MODE_MMAP,
            threads,
        )'''

new = '''        LitePyTorchAndroid.setNumThreads(threads)
        val dir = voiceDir()
        val accentorFile = File(dir, "accentor.ptl")
        val melFile = File(dir, "tts_mel.ptl")
        val headFile = File(dir, "head.ptl")
        val backboneFile = File(dir, "backbone.pte")

        accentor = LiteModuleLoader.load(accentorFile.absolutePath)
        mel = LiteModuleLoader.load(melFile.absolutePath)
        head = LiteModuleLoader.load(headFile.absolutePath)

        backbone = org.pytorch.executorch.Module.load(
            backboneFile.absolutePath,
            org.pytorch.executorch.Module.LOAD_MODE_MMAP,
            threads,
        )'''

if old not in s:
    raise SystemExit('ensureLoaded asset block not found')
s = s.replace(old, new, 1)
engine.write_text(s)

main = Path('android/app/src/main/kotlin/com/dreampulse/assistant/MainActivity.kt')
m = main.read_text()
needle = '''                            "modelPresent" to localVoice.modelPresent(),
                            "engine" to "DreamPulseVoice",'''
replacement = '''                            "modelPresent" to localVoice.modelPresent(),
                            "voiceDir" to localVoice.voiceDir().absolutePath,
                            "engine" to "DreamPulseVoice",'''
if needle not in m:
    raise SystemExit('MainActivity status marker not found')
main.write_text(m.replace(needle, replacement, 1))
