package com.dreampulse.assistant

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dream_pulse/voice"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val dir = File(filesDir, "dream-pulse-voice")
                    val names = listOf(
                        "tts_mel.ptl",
                        "head.ptl",
                        "backbone.pte",
                    )
                    val present = names.all { name ->
                        File(dir, name).let { it.isFile && it.length() > 1024L }
                    }
                    val stageFile = File(dir, "last-stage.txt")
                    val lastStage = runCatching {
                        if (stageFile.isFile) stageFile.readText().trim() else "idle"
                    }.getOrDefault("unknown")

                    result.success(
                        mapOf(
                            "modelPresent" to present,
                            "voiceDir" to dir.absolutePath,
                            "lastStage" to lastStage,
                            "engine" to "DreamPulseVoiceSafe",
                            "systemTts" to false,
                            "separateProcess" to true,
                            "voices" to listOf("baya", "kseniya"),
                        )
                    )
                }

                "speak" -> {
                    val text = call.argument<String>("text").orEmpty()
                    if (text.isBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val receiver = object : ResultReceiver(Handler(Looper.getMainLooper())) {
                        override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                            if (resultCode == DreamPulseVoiceService.RESULT_OK) {
                                result.success(null)
                            } else {
                                result.error(
                                    "VOICE_PROCESS",
                                    resultData?.getString("error")
                                        ?: "Voice process stopped",
                                    null,
                                )
                            }
                        }
                    }

                    val intent = Intent(this, DreamPulseVoiceService::class.java).apply {
                        action = DreamPulseVoiceService.ACTION_SPEAK
                        putExtra(DreamPulseVoiceService.EXTRA_TEXT, text)
                        putExtra(
                            DreamPulseVoiceService.EXTRA_VOICE,
                            call.argument<String>("voice") ?: "baya",
                        )
                        putExtra(
                            DreamPulseVoiceService.EXTRA_RATE,
                            call.argument<Number>("rate")?.toFloat() ?: 1.0f,
                        )
                        putExtra(
                            DreamPulseVoiceService.EXTRA_PITCH,
                            call.argument<Number>("pitch")?.toFloat() ?: 1.0f,
                        )
                        putExtra(
                            DreamPulseVoiceService.EXTRA_TIMBRE,
                            call.argument<Number>("timbre")?.toFloat() ?: 0.0f,
                        )
                        putExtra(
                            DreamPulseVoiceService.EXTRA_VOLUME,
                            call.argument<Number>("volume")?.toFloat() ?: 1.0f,
                        )
                        putExtra(
                            DreamPulseVoiceService.EXTRA_PAUSE,
                            call.argument<Number>("sentencePauseMs")?.toInt() ?: 160,
                        )
                        putExtra(DreamPulseVoiceService.EXTRA_RECEIVER, receiver)
                    }

                    try {
                        startService(intent)
                    } catch (e: Throwable) {
                        result.error(
                            "VOICE_PROCESS_START",
                            e.message ?: e.javaClass.simpleName,
                            null,
                        )
                    }
                }

                "stop" -> {
                    stopService(Intent(this, DreamPulseVoiceService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
