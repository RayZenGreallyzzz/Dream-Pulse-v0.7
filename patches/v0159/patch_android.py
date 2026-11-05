"""Wire a *real* experimental Silero v5_5_ru TorchScript Lite diagnostic
synthesizer into the existing Piper-free Dream Pulse v0.15.8 Android app.

Run only AFTER Flutter bootstrap and patches/v0158/patch_android.py.
No Dream Pulse Core changes. Keep existing split-pack compatibility.
"""
from pathlib import Path
import shutil


def replace_once(path: Path, old: str, new: str):
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one anchor, got {count}: {old[:85]!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


native = Path("android/app/src/main/kotlin/com/dreampulse/assistant")
for name in (
    "DreamPulseSileroLitePackStore.kt",
    "DreamPulseSileroLiteSynth.kt",
    "DreamPulseSileroPreviewService.kt",
):
    shutil.copyfile("patches/v0159/android/" + name, native / name)

main = native / "MainActivity.kt"
replace_once(
    main,
    "        val packStore = DreamPulseSileroPackStore(applicationContext)\n",
    "        val packStore = DreamPulseSileroPackStore(applicationContext)\n"
    "        val liteStore = DreamPulseSileroLitePackStore(applicationContext)\n",
)
replace_once(
    main,
    '                "status" -> result.success(packStore.status())',
    '                "status" -> result.success(packStore.status() + liteStore.status())',
)
replace_once(
    main,
    """                                val report = packStore.install(path)
                                runOnUiThread { result.success(report) }""",
    """                                // v0.15.9 adds an actual executable
                                // TorchScript Lite pack; legacy split packs
                                // remain supported for later ExecuTorch.
                                val isFullLite = java.util.zip.ZipFile(path).use { zip ->
                                    zip.getEntry("silero/model.ptl") != null
                                }
                                val report = if (isFullLite) liteStore.install(path)
                                    else packStore.install(path)
                                runOnUiThread { result.success(report) }""",
)
replace_once(
    main,
    """                "speak" -> result.error(
                    "NATIVE_TTS_NOT_READY",""",
    """                "previewBase" -> {
                    // Stock female Baya is only a diagnostic model test,
                    // never identified as Irina or a custom user voice.
                    val phrase = call.argument<String>("text")
                        ?.take(180) ?: "прив+ет, м+ир."
                    val receiver = object : android.os.ResultReceiver(
                        android.os.Handler(android.os.Looper.getMainLooper())
                    ) {
                        override fun onReceiveResult(code: Int, data: android.os.Bundle?) {
                            if (code == DreamPulseSileroPreviewService.RESULT_OK) {
                                result.success(data?.getString("message") ?: "Silero PCM ready")
                            } else {
                                result.error(
                                    "SILERO_TEST_FAILED",
                                    data?.getString("error") ?: "Silero service stopped",
                                    null,
                                )
                            }
                        }
                    }
                    try {
                        startService(
                            android.content.Intent(
                                this, DreamPulseSileroPreviewService::class.java
                            ).apply {
                                action = DreamPulseSileroPreviewService.ACTION_PREVIEW
                                putExtra(DreamPulseSileroPreviewService.EXTRA_TEXT, phrase)
                                putExtra(DreamPulseSileroPreviewService.EXTRA_RECEIVER, receiver)
                            }
                        )
                    } catch (error: Throwable) {
                        result.error("SILERO_START_FAILED", error.message, null)
                    }
                }
                "speak" -> result.error(
                    "NATIVE_TTS_NOT_READY",""",
)
replace_once(
    main,
    '                "stop" -> result.success(null)',
    '''                "stop" -> {
                    try {
                        startService(
                            android.content.Intent(
                                this, DreamPulseSileroPreviewService::class.java
                            ).apply {
                                action = DreamPulseSileroPreviewService.ACTION_CANCEL
                            }
                        )
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("SILERO_STOP_FAILED", error.message, null)
                    }
                }''',
)

manifest = Path("android/app/src/main/AndroidManifest.xml")
replace_once(
    manifest,
    "    </application>",
    '''        <service
            android:name=".DreamPulseSileroPreviewService"
            android:exported="false"
            android:process=":silero" />
    </application>''',
)

gradle = Path("android/app/build.gradle.kts")
replace_once(
    gradle,
    "dependencies {\n",
    'dependencies {\n    implementation("org.pytorch:pytorch_android_lite:2.1.0")\n',
)
replace_once(
    gradle,
    "android {\n",
    '''android {
    // Native PyTorch Lite and other optional JNI dependencies may each
    // carry libc++_shared/fbjni: select one copy deterministically.
    packaging {
        jniLibs.pickFirsts += listOf(
            "lib/*/libfbjni.so",
            "lib/*/libc++_shared.so",
        )
    }
''',
)
print("Dream Pulse Silero Lite native preview runtime and pack import wired.")
