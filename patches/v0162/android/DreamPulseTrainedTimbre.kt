package com.dreampulse.assistant

import android.content.Context
import org.json.JSONObject
import kotlin.math.roundToInt

/**
 * 257-tap symmetric FIR tone filters genuinely fitted by PyTorch on four
 * PRIVATE user-designed synthetic female reference recordings.
 *
 * These weights color a stock Silero reference voice. They are NOT the neural
 * Silero weights and cannot reproduce an author's unique speaker identity.
 * No original samples or other personally supplied audio are in APK assets.
 */
class DreamPulseTrainedTimbre(private val context: Context) {
    private val allowed = setOf(
        "dream_ref_hello", "dream_ref_calm",
        "dream_ref_weather", "dream_ref_long",
    )
    private val cache = mutableMapOf<String, FloatArray>()

    @Synchronized private fun coefficients(voiceId: String): FloatArray {
        require(voiceId in allowed) { "No fitted timbre profile for $voiceId" }
        cache[voiceId]?.let { return it }
        val path = "dream_pulse_tts/styles/$voiceId.json"
        val raw = context.assets.open(path).bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
        val profile = JSONObject(raw)
        require(profile.getString("format") == "dream-pulse-timbre-fir-v1") {
            "Unexpected style weight format"
        }
        require(profile.getString("voice_id") == voiceId) {
            "Mislabelled voice weights: $voiceId"
        }
        require(profile.getInt("sample_rate") == 24000) {
            "Voice style filter must run at 24 kHz"
        }
        // These are explicitly small acoustic DSP parameters, not a clone.
        require(!profile.getBoolean("is_author_voice_clone"))
        require(!profile.getBoolean("silero_neural_weights_changed"))
        val values = profile.getJSONArray("fir_center_to_edge")
        require(values.length() == 129) { "Expected 257 symmetric FIR taps" }
        val taps = FloatArray(129) { i ->
            val tap = values.getDouble(i).toFloat()
            require(tap.isFinite() && kotlin.math.abs(tap) < 3.0f) {
                "Invalid learned voice coefficient: $i"
            }
            tap
        }
        cache[voiceId] = taps
        return taps
    }

    /** Processing is offline per generated utterance and cancellable via
     *  the parent synthesis worker. This does not affect the main Flutter UI.
     */
    fun apply(voiceId: String, pcm: ShortArray): ShortArray {
        val taps = coefficients(voiceId)
        val n = pcm.size
        val styled = ShortArray(n)
        for (i in 0 until n) {
            var total = taps[0] * (pcm[i].toFloat() / 32768f)
            for (distance in 1 until taps.size) {
                var value = 0f
                val left = i - distance
                val right = i + distance
                if (left >= 0) value += pcm[left].toFloat() / 32768f
                if (right < n) value += pcm[right].toFloat() / 32768f
                total += taps[distance] * value
            }
            styled[i] = (total.coerceIn(-0.98f, 0.98f) * 32767f)
                .roundToInt().coerceIn(-32768, 32767).toShort()
        }
        return styled
    }
}
