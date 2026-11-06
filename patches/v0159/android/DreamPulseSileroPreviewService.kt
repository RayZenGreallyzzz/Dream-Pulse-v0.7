package com.dreampulse.assistant

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.IBinder
import android.os.ResultReceiver
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Internal smoke-test generation runs in a separate :silero process.
 * A fatal native PyTorch crash cannot kill Dream Pulse's main chat process.
 */
class DreamPulseSileroPreviewService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val inFlight = AtomicInteger(0)
    private lateinit var synth: DreamPulseSileroLiteSynth

    override fun onCreate() {
        super.onCreate()
        synth = DreamPulseSileroLiteSynth(applicationContext)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    private fun receiver(intent: Intent): ResultReceiver? =
        intent.getParcelableExtra(EXTRA_RECEIVER)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        when (intent.action) {
            ACTION_PREVIEW -> {
                val callback = receiver(intent)
                val phrase = intent.getStringExtra(EXTRA_TEXT)
                    ?.take(180) ?: "прив+ет, м+ир."
                inFlight.incrementAndGet()
                executor.execute {
                    try {
                        val n = synth.preview(phrase)
                        callback?.send(RESULT_OK, Bundle().apply {
                            putInt("samples", n)
                            putString("message", "Silero Lite PCM 24 kHz generated")
                        })
                    } catch (error: Throwable) {
                        Log.e(TAG, "Lite preview failed", error)
                        callback?.send(RESULT_ERROR, Bundle().apply {
                            putString("error", error.message ?: error.javaClass.simpleName)
                        })
                    } finally {
                        if (inFlight.decrementAndGet() <= 0) stopSelfResult(startId)
                    }
                }
            }
            ACTION_CANCEL -> {
                synth.cancel()
                if (inFlight.get() == 0) stopSelfResult(startId)
            }
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        synth.cancel()
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "DreamPulseSilero"
        const val ACTION_PREVIEW = "com.dreampulse.assistant.silero.PREVIEW"
        const val ACTION_CANCEL = "com.dreampulse.assistant.silero.CANCEL"
        const val EXTRA_TEXT = "phrase"
        const val EXTRA_RECEIVER = "receiver"
        const val RESULT_OK = 1
        const val RESULT_ERROR = 2
    }
}
