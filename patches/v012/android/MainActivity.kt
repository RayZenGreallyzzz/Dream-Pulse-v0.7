package com.dreampulse.assistant

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var voiceEngine: DreamPulseVoiceEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dream_pulse/media"
        ).setMethodCallHandler { call, result ->
            if (call.method != "videoFrame") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            val timeMs = call.argument<Number>("timeMs")?.toLong() ?: 0L
            if (path.isNullOrBlank()) {
                result.error("BAD_PATH", "Video path is empty", null)
                return@setMethodCallHandler
            }

            try {
                val retriever = MediaMetadataRetriever()
                retriever.setDataSource(path)
                val frame = retriever.getFrameAtTime(
                    timeMs * 1000L,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                )
                retriever.release()

                if (frame == null) {
                    result.error("NO_FRAME", "Could not extract video frame", null)
                    return@setMethodCallHandler
                }

                val maxWidth = 960
                val scaled = if (frame.width > maxWidth) {
                    val newHeight =
                        (frame.height * (maxWidth.toFloat() / frame.width)).toInt()
                    Bitmap.createScaledBitmap(frame, maxWidth, newHeight, true)
                } else {
                    frame
                }

                val stream = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 72, stream)
                val bytes = stream.toByteArray()
                stream.close()

                if (scaled !== frame) scaled.recycle()
                frame.recycle()
                result.success(bytes)
            } catch (e: Exception) {
                result.error(
                    "VIDEO_FRAME_ERROR",
                    e.message ?: "Video frame error",
                    null
                )
            }
        }

        val localVoice = DreamPulseVoiceEngine(applicationContext)
        voiceEngine = localVoice

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dream_pulse/voice"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    result.success(
                        mapOf(
                            "modelPresent" to localVoice.modelPresent(),
                            "engine" to "DreamPulseVoice",
                            "systemTts" to false,
                            "voices" to listOf("baya", "kseniya"),
                        )
                    )
                }

                "warmup" -> {
                    localVoice.warmup { outcome ->
                        runOnUiThread {
                            outcome.fold(
                                onSuccess = { result.success(null) },
                                onFailure = {
                                    result.error(
                                        "VOICE_WARMUP",
                                        it.message ?: it.javaClass.simpleName,
                                        null
                                    )
                                }
                            )
                        }
                    }
                }

                "speak" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val voice = call.argument<String>("voice") ?: "baya"
                    val rate =
                        call.argument<Number>("rate")?.toFloat() ?: 1.0f
                    val pitch =
                        call.argument<Number>("pitch")?.toFloat() ?: 1.0f
                    val timbre =
                        call.argument<Number>("timbre")?.toFloat() ?: 0.0f
                    val volume =
                        call.argument<Number>("volume")?.toFloat() ?: 1.0f
                    val pause =
                        call.argument<Number>("sentencePauseMs")?.toInt() ?: 160

                    if (text.isBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    localVoice.speak(
                        text = text,
                        voice = voice,
                        rate = rate,
                        pitch = pitch,
                        timbre = timbre,
                        volume = volume,
                        sentencePauseMs = pause,
                    ) { outcome ->
                        runOnUiThread {
                            outcome.fold(
                                onSuccess = { result.success(null) },
                                onFailure = {
                                    result.error(
                                        "VOICE_SYNTH",
                                        it.message ?: it.javaClass.simpleName,
                                        null
                                    )
                                }
                            )
                        }
                    }
                }

                "stop" -> {
                    localVoice.stop()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        voiceEngine?.dispose()
        voiceEngine = null
        super.onDestroy()
    }
}
