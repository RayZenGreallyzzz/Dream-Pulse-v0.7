"""Hardening of Irina's isolated native voice runtime.

Applied after v0.15.5 and the Android bootstrap. Does not touch Dream Pulse
Core, choice of voice, model weights, or speaker output.
"""
from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    file = Path(path)
    code = file.read_text(encoding="utf-8")
    found = code.count(old)
    if found != 1:
        raise RuntimeError(f"{path}: expected 1 anchor, got {found}: {old[:90]!r}")
    file.write_text(code.replace(old, new, 1), encoding="utf-8")


native = Path("android/app/src/main/kotlin/com/dreampulse/assistant")
engine = str(native / "DreamPulseVoiceEngine.kt")
service = str(native / "DreamPulseVoiceService.kt")
main = str(native / "MainActivity.kt")


def patch_engine() -> None:
    once(engine,
         "    private val generation = AtomicInteger(0)\n",
         "    private val generation = AtomicInteger(0)\n"
         "    // Protect AudioTrack from concurrent native write/release calls.\n"
         "    private val audioLock = Any()\n")

    once(engine,
         """    fun dispose() {
        stop()
        executor.shutdownNow()
        runCatching { tts?.release() }
        tts = null
    }""",
         """    fun dispose() {
        // Never free JNI TTS objects while generation is still executing.
        stop()
        try {
            executor.execute {
                runCatching { tts?.release() }
                tts = null
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // Android will reclaim this isolated process. Do not race JNI.
        }
        executor.shutdown()
    }""")

    once(engine,
         """                    mark("done")
                }
            )
        }
    }

    fun diagnose""",
         """                    mark(
                        if (token == generation.get()) "done" else "cancelled"
                    )
                }
            )
        }
    }

    fun diagnose""")

    once(engine,
         """                    val written = track.write(
                        pcm,
                        0,
                        pcm.size,
                        AudioTrack.WRITE_BLOCKING,
                    )""",
         """                    // The UI can cancel while sherpa-onnx is invoking
                    // this callback on a native thread. Serialize short
                    // bounded writes with stop/release to avoid SIGSEGV.
                    var written = 0
                    var offset = 0
                    while (offset < pcm.size && token == generation.get()) {
                        val count = minOf(4096, pcm.size - offset)
                        val n = synchronized(audioLock) {
                            if (token != generation.get()) 0
                            else track.write(
                                pcm,
                                offset,
                                count,
                                AudioTrack.WRITE_BLOCKING,
                            )
                        }
                        if (n <= 0) {
                            if (token == generation.get()) {
                                mark("audio_write_error:$n")
                            }
                            break
                        }
                        offset += n
                        written += n
                    }""")

    once(engine,
         """                while (
                    token == generation.get() &&
                    track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                    track.playbackHeadPosition < expected
                ) {
                    Thread.sleep(10)
                }""",
         """                // Some Android audio drivers stop advancing the
                // playback head. Never wait forever for a drain.
                val deadline = android.os.SystemClock.elapsedRealtime() + 15000L
                while (
                    token == generation.get() &&
                    track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                    track.playbackHeadPosition < expected &&
                    android.os.SystemClock.elapsedRealtime() < deadline
                ) {
                    Thread.sleep(10)
                }""")

    once(engine,
         """    private fun releaseTrack(track: AudioTrack) {
        runCatching { track.pause() }
        runCatching { track.flush() }
        runCatching { track.stop() }
        runCatching { track.release() }

        if (currentTrack === track) {
            currentTrack = null
        }
    }""",
         """    private fun releaseTrack(track: AudioTrack) {
        synchronized(audioLock) {
            runCatching { track.pause() }
            runCatching { track.flush() }
            runCatching { track.stop() }
            runCatching { track.release() }

            if (currentTrack === track) currentTrack = null
        }
    }""")

    once(engine,
         """    private fun stopTrack() {
        currentTrack?.let { track ->
            releaseTrack(track)
        }
        currentTrack = null
    }""",
         """    private fun stopTrack() {
        // Interrupt the track, but let the generating worker own release.
        // Releasing from another thread can invalidate a JNI callback.
        synchronized(audioLock) {
            currentTrack?.let { track ->
                runCatching { track.pause() }
                runCatching { track.flush() }
            }
        }
    }""")


def patch_service() -> None:
    once(service,
         "import android.os.ResultReceiver\n",
         "import android.os.ResultReceiver\n"
         "import java.util.concurrent.atomic.AtomicInteger\n")

    once(service,
         "    private var engine: DreamPulseVoiceEngine? = null\n",
         "    private var engine: DreamPulseVoiceEngine? = null\n"
         "    private val runningJobs = AtomicInteger(0)\n"
         "    @Volatile private var cancelStartId: Int? = null\n")

    once(service,
         """            ACTION_SPEAK -> {
                val text =""",
         """            ACTION_SPEAK -> {
                cancelStartId = null
                runningJobs.incrementAndGet()
                val text =""")

    once(service,
         """            ACTION_DIAGNOSE -> {
                local.diagnose { outcome ->""",
         """            ACTION_DIAGNOSE -> {
                cancelStartId = null
                runningJobs.incrementAndGet()
                local.diagnose { outcome ->""")

    # Each successful callback controls the service lifecycle, rather than
    # stopping and releasing JNI from an unrelated caller.
    once(service,
         """                    stopSelfResult(startId)
                }
            }

            ACTION_DIAGNOSE""",
         """                    finishJob(startId)
                }
            }

            ACTION_DIAGNOSE""")

    once(service,
         """                    stopSelfResult(startId)
                }
            }

            else ->""",
         """                    finishJob(startId)
                }
            }

            ACTION_STOP -> {
                // An active callback must finish before the native engine
                // can be destroyed. No force-stop of the voice process.
                cancelStartId = startId
                local.stop()
                if (runningJobs.get() == 0) {
                    stopSelfResult(startId)
                }
            }

            else ->""")

    once(service,
         """    private fun sendOutcome(
        receiver: ResultReceiver?,""",
         """    private fun finishJob(startId: Int) {
        if (runningJobs.decrementAndGet() <= 0) {
            stopSelfResult(cancelStartId ?: startId)
        }
    }

    private fun sendOutcome(
        receiver: ResultReceiver?,""")

    once(service,
         """        const val ACTION_DIAGNOSE =
            "com.dreampulse.assistant.voice.DIAGNOSE"
""",
         """        const val ACTION_DIAGNOSE =
            "com.dreampulse.assistant.voice.DIAGNOSE"
        const val ACTION_STOP =
            "com.dreampulse.assistant.voice.STOP"
""")


def patch_activity() -> None:
    once(main,
         """                "stop" -> {
                    stopService(
                        Intent(
                            this,
                            DreamPulseVoiceService::
                                class.java,
                        )
                    )
                    result.success(null)
                }""",
         """                "stop" -> {
                    try {
                        // An explicit cancel action preserves the service
                        // until JNI callbacks have safely unwound.
                        startService(
                            Intent(
                                this,
                                DreamPulseVoiceService::class.java,
                            ).apply {
                                action = DreamPulseVoiceService.ACTION_STOP
                            },
                        )
                        result.success(null)
                    } catch (e: Throwable) {
                        result.error(
                            "VOICE_STOP",
                            e.message ?: e.javaClass.simpleName,
                            null,
                        )
                    }
                }""")

    # Report whether a prior :voice process was killed by Android or crashed
    # in native code. Android 11+ exposes app process exit reasons.
    once(main,
         "import android.os.Bundle\n",
         "import android.os.Bundle\n"
         "import android.os.Build\n"
         "import android.app.ActivityManager\n")

    once(main,
         """                            "separateProcess" to true,
                            "voices" to""",
         """                            "separateProcess" to true,
                            "voiceExit" to lastVoiceExit(),
                            "voices" to""")

    once(main,
         """class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(""",
         """class MainActivity : FlutterActivity() {
    private fun lastVoiceExit(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "unavailable"
        return runCatching {
            val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            val last = manager.getHistoricalProcessExitReasons(
                packageName, 0, 10,
            ).firstOrNull { it.processName.endsWith(":voice") }
                ?: return@runCatching "none"
            "reason=${last.reason};status=${last.status};" +
                "time=${last.timestamp};pss=${last.pss}"
        }.getOrDefault("unknown")
    }

    override fun configureFlutterEngine(""")


if __name__ == "__main__":
    patch_engine()
    patch_service()
    patch_activity()
