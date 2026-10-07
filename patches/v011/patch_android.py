from pathlib import Path

p = Path('android/app/src/main/kotlin/com/dreampulse/assistant/MainActivity.kt')
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(r'''package com.dreampulse.assistant

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

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
                    val newHeight = (frame.height * (maxWidth.toFloat() / frame.width)).toInt()
                    Bitmap.createScaledBitmap(frame, maxWidth, newHeight, true)
                } else {
                    frame
                }

                val stream = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.JPEG, 72, stream)
                val bytes = stream.toByteArray()
                stream.close()

                if (scaled !== frame) {
                    scaled.recycle()
                }
                frame.recycle()

                result.success(bytes)
            } catch (e: Exception) {
                result.error("VIDEO_FRAME_ERROR", e.message ?: "Video frame error", null)
            }
        }
    }
}
''')
