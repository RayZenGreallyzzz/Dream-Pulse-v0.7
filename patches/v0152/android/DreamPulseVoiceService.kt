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
        markStage("voice_engine_create")

        engine = runCatching {
            DreamPulseVoiceEngine(applicationContext)
        }.onSuccess {
            markStage("voice_engine_created")
        }.onFailure { error ->
            markStage(
                "voice_engine_fail:" +
                    (
                        error.message
                            ?: error.javaClass.simpleName
                    ).take(180)
            )
        }.getOrNull()
    }

    private fun markStage(stage: String) {
        runCatching {
            val dir = java.io.File(
                filesDir,
                "dream-pulse-voice",
            )
            dir.mkdirs()
            java.io.File(
                dir,
                "last-stage.txt",
            ).writeText(stage)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val receiver =
            intent?.parcelableReceiver(EXTRA_RECEIVER)

        val local = engine
        if (local == null) {
            receiver?.send(
                RESULT_ERROR,
                Bundle().apply {
                    putString(
                        "error",
                        "Dream Voice engine unavailable",
                    )
                    putString(
                        "stage",
                        "voice_engine_unavailable",
                    )
                },
            )
            stopSelfResult(startId)
            return START_NOT_STICKY
        }

        when (intent?.action) {
            ACTION_SPEAK -> {
                val text =
                    intent.getStringExtra(EXTRA_TEXT).orEmpty()
                val voice =
                    intent.getStringExtra(EXTRA_VOICE)
                        ?: "zoey"
                val rate =
                    intent.getFloatExtra(EXTRA_RATE, 1.02f)
                val pitch =
                    intent.getFloatExtra(EXTRA_PITCH, 1.05f)
                val timbre =
                    intent.getFloatExtra(EXTRA_TIMBRE, 0.18f)
                val volume =
                    intent.getFloatExtra(EXTRA_VOLUME, 1.0f)
                val pause =
                    intent.getIntExtra(EXTRA_PAUSE, 260)

                local.speak(
                    text = text,
                    voice = voice,
                    rate = rate,
                    pitch = pitch,
                    timbre = timbre,
                    volume = volume,
                    sentencePauseMs = pause,
                ) { outcome ->
                    sendOutcome(
                        receiver = receiver,
                        outcome = outcome.map { "VOICE OK" },
                        local = local,
                    )
                    stopSelfResult(startId)
                }
            }

            ACTION_DIAGNOSE -> {
                local.diagnose { outcome ->
                    sendOutcome(
                        receiver = receiver,
                        outcome = outcome,
                        local = local,
                    )
                    stopSelfResult(startId)
                }
            }

            else -> {
                stopSelfResult(startId)
            }
        }

        return START_NOT_STICKY
    }

    private fun sendOutcome(
        receiver: ResultReceiver?,
        outcome: Result<String>,
        local: DreamPulseVoiceEngine,
    ) {
        outcome.fold(
            onSuccess = { message ->
                receiver?.send(
                    RESULT_OK,
                    Bundle().apply {
                        putString("message", message)
                        putString("stage", local.lastStage())
                    },
                )
            },
            onFailure = { error ->
                receiver?.send(
                    RESULT_ERROR,
                    Bundle().apply {
                        putString(
                            "error",
                            error.message
                                ?: error.javaClass.simpleName,
                        )
                        putString("stage", local.lastStage())
                    },
                )
            },
        )
    }

    override fun onDestroy() {
        engine?.dispose()
        engine = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun Intent.parcelableReceiver(
        key: String,
    ): ResultReceiver? = getParcelableExtra(key)

    companion object {
        const val ACTION_SPEAK =
            "com.dreampulse.assistant.voice.SPEAK"
        const val ACTION_DIAGNOSE =
            "com.dreampulse.assistant.voice.DIAGNOSE"

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
