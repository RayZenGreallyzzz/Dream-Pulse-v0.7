package com.dreampulse.assistant

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.ResultReceiver

class DreamPulseVoiceService : Service() {
    private var engine: DreamPulseVoiceEngine? = null

    override fun onCreate() {
        super.onCreate()
        markStage("native_libcxx_load")
        try {
            // Dream Pulse packages Flutter/llama with a different libc++_shared.so.
            // The isolated :voice process must preload the exact C++ runtime used
            // to build RuVoice's PyTorch/ExecuTorch native libraries.
            System.loadLibrary("voice_cxx")
            markStage("native_libcxx_ok")
            engine = DreamPulseVoiceEngine(applicationContext)
            markStage("voice_engine_created")
        } catch (t: Throwable) {
            engine = null
            markStage(
                "native_libcxx_fail:" +
                    (t.message ?: t.javaClass.simpleName).take(180)
            )
        }
    }

    private fun markStage(stage: String) {
        runCatching {
            val dir = java.io.File(filesDir, "dream-pulse-voice")
            dir.mkdirs()
            java.io.File(dir, "last-stage.txt").writeText(stage)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_SPEAK) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val receiver = intent.parcelableReceiver(EXTRA_RECEIVER)
        val local = engine
        if (local == null) {
            receiver?.send(
                RESULT_ERROR,
                Bundle().apply { putString("error", "Voice engine unavailable") },
            )
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        val voice = intent.getStringExtra(EXTRA_VOICE) ?: "baya"
        val rate = intent.getFloatExtra(EXTRA_RATE, 1.0f)
        val pitch = intent.getFloatExtra(EXTRA_PITCH, 1.0f)
        val timbre = intent.getFloatExtra(EXTRA_TIMBRE, 0.0f)
        val volume = intent.getFloatExtra(EXTRA_VOLUME, 1.0f)
        val pause = intent.getIntExtra(EXTRA_PAUSE, 160)

        local.speak(
            text = text,
            voice = voice,
            rate = rate,
            pitch = pitch,
            timbre = timbre,
            volume = volume,
            sentencePauseMs = pause,
        ) { outcome ->
            outcome.fold(
                onSuccess = {
                    receiver?.send(RESULT_OK, Bundle())
                },
                onFailure = { error ->
                    receiver?.send(
                        RESULT_ERROR,
                        Bundle().apply {
                            putString(
                                "error",
                                error.message ?: error.javaClass.simpleName,
                            )
                        },
                    )
                },
            )
            stopSelf(startId)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        engine?.dispose()
        engine = null
        super.onDestroy()

        // This service is declared in :voice. Killing only that process makes
        // native PyTorch/ExecuTorch memory deterministic and cannot close chat.
        android.os.Process.killProcess(android.os.Process.myPid())
    }

    @Suppress("DEPRECATION")
    private fun Intent.parcelableReceiver(key: String): ResultReceiver? =
        getParcelableExtra(key)

    companion object {
        const val ACTION_SPEAK = "com.dreampulse.assistant.voice.SPEAK"

        const val EXTRA_TEXT = "text"
        const val EXTRA_VOICE = "voice"
        const val EXTRA_RATE = "rate"
        const val EXTRA_PITCH = "pitch"
        const val EXTRA_TIMBRE = "timbre"
        const val EXTRA_VOLUME = "volume"
        const val EXTRA_PAUSE = "pause"
        const val EXTRA_RECEIVER = "receiver"

        const val RESULT_OK = 1
        const val RESULT_ERROR = 2
    }
}
