"""Replace Piper/sharpa-onnx Android service with an in-app Silero pack API.

No TTS inference is shipped in this milestone. Original verified model
weights can be imported, but voice playback remains explicitly unavailable.
"""
from pathlib import Path
import re
import shutil

native = Path("android/app/src/main/kotlin/com/dreampulse/assistant")
main = native / "MainActivity.kt"
shutil.copyfile(
    "patches/v0158/android/DreamPulseSileroPackStore.kt",
    native / "DreamPulseSileroPackStore.kt",
)

s = main.read_text(encoding="utf-8")
anchor = """        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dream_pulse/voice",
        ).setMethodCallHandler"""
begin = s.find(anchor)
# MainActivity closes with two braces at end: configureFlutterEngine, class.
closing = s.rfind("\n    }\n}")
if begin < 0 or closing <= begin:
    raise RuntimeError("Unexpected MainActivity voice block layout")

replacement = r'''        // Private Dream Pulse TTS. No Piper, system TTS, or RuVoice.
        val packStore = DreamPulseSileroPackStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dream_pulse/tts",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(packStore.status())
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_PATH", "Silero ZIP path missing", null)
                    } else {
                        sileroIo.execute {
                            try {
                                val report = packStore.install(path)
                                runOnUiThread { result.success(report) }
                            } catch (error: Throwable) {
                                runOnUiThread {
                                    result.error(
                                        "SILERO_PACK_INVALID",
                                        error.message ?: error.javaClass.simpleName,
                                        null,
                                    )
                                }
                            }
                        }
                    }
                }
                "speak" -> result.error(
                    "NATIVE_TTS_NOT_READY",
                    "Dream Pulse Silero inference has not been linked",
                    null,
                )
                "stop" -> result.success(null)
                else -> result.notImplemented()
            }
        }'''
s = s[:begin] + replacement + s[closing:]
if s.count('"dream_pulse/voice"') != 0:
    raise RuntimeError("Legacy Piper channel survived removal")
if s.count('"dream_pulse/tts"') != 1:
    raise RuntimeError("New TTS channel not installed exactly once")

if "import java.util.concurrent.Executors\n" not in s:
    s = s.replace(
        "import java.io.File\n",
        "import java.io.File\nimport java.util.concurrent.Executors\n",
        1,
    )

cls = "class MainActivity : FlutterActivity() {\n"
if s.count(cls) != 1:
    raise RuntimeError("MainActivity class layout unknown")
s = s.replace(
    cls,
    cls + """
    private val sileroIo = Executors.newSingleThreadExecutor()

    override fun onDestroy() {
        sileroIo.shutdown()
        super.onDestroy()
    }

""",
    1,
)
main.write_text(s, encoding="utf-8")

# Remove the old service AND its native engine from the new installation.
for name in ("DreamPulseVoiceEngine.kt", "DreamPulseVoiceService.kt"):
    f = native / name
    if not f.is_file():
        raise RuntimeError(f"Legacy Piper source missing: {f}")
    f.unlink()

manifest = Path("android/app/src/main/AndroidManifest.xml")
s = manifest.read_text(encoding="utf-8")
s, count = re.subn(
    r'\s*<service\s+android:name="\.DreamPulseVoiceService"'
    r'[\s\S]*?/\s*>',
    '',
    s,
    count=1,
)
if count != 1:
    raise RuntimeError("Old Piper voice service was not registered")
manifest.write_text(s, encoding="utf-8")

gradle = Path("android/app/build.gradle.kts")
s = gradle.read_text(encoding="utf-8")
lines = s.splitlines()
old = [line for line in lines if "com.github.k2-fsa.sherpa-onnx" in line]
if len(old) != 1:
    raise RuntimeError(f"Expected 1 old sherpa dependency, found {len(old)}")
s = "\n".join(
    line for line in lines if "com.github.k2-fsa.sherpa-onnx" not in line
) + "\n"
gradle.write_text(s, encoding="utf-8")
