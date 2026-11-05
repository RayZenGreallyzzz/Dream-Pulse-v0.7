package com.dreampulse.assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.SystemClock
import org.json.JSONObject
import org.pytorch.IValue
import org.pytorch.LiteModuleLoader
import org.pytorch.Tensor
import java.util.concurrent.atomic.AtomicInteger

/**
 * Real stock Silero v5_5_ru audio generation, in a SEPARATE Android service
 * process. This is only an internal female-voice hardware smoke test.
 * It NEVER maps the stock Baya voice onto Irina or 4 author-designed voices.
 */
class DreamPulseSileroLiteSynth(private val context: Context) {
    private val generation = AtomicInteger(0)
    private val audioLock = Any()
    private var currentTrack: AudioTrack? = null

    fun cancel() {
        generation.incrementAndGet()
        synchronized(audioLock) {
            currentTrack?.let {
                runCatching { it.pause() }
                runCatching { it.flush() }
            }
        }
    }

    fun preview(text: String = "прив+ет, м+ир."): Int {
        val token = generation.incrementAndGet()
        val store = DreamPulseSileroLitePackStore(context)
        require(store.ready()) { "Full Lite model pack is not installed" }

        val meta = JSONObject(store.symbols.readText(Charsets.UTF_8))
        val s2i = meta.getJSONObject("symbol_to_id")
        val sos = s2i.getInt(meta.getString("sos"))
        val eos = s2i.getInt(meta.getString("eos"))
        val speaker = meta.getJSONObject("speakers").getInt("baya")
        val raw = text.lowercase().take(180)
        val seq = ArrayList<Long>(raw.length + 2)
        seq.add(sos.toLong())
        for (char in raw) {
            val key = char.toString()
            if (s2i.has(key)) seq.add(s2i.getInt(key).toLong())
        }
        seq.add(eos.toLong())
        require(seq.size >= 4) { "No supported Silero symbols in the test text" }
        require(token == generation.get()) { "Voice preview cancelled" }

        val shape = longArrayOf(1L, seq.size.toLong())
        val rate = Tensor.fromBlob(FloatArray(seq.size) { 1f }, shape)
        val ids = Tensor.fromBlob(seq.toLongArray(), shape)
        val zeros = Tensor.fromBlob(LongArray(seq.size), shape)

        // The ORIGINAL 13-argument v5_5_ru forward:
        // sequence, speaker, sampleRate, pauses, rates, pitches,
        // args7-8 optional, device, suffix, flag, typeIds, focusMask.
        val args = arrayOf(
            IValue.from(ids),
            IValue.from(Tensor.fromBlob(longArrayOf(speaker.toLong()), longArrayOf(1))),
            IValue.from(24000L),
            IValue.optionalNull(),
            IValue.from(rate),
            IValue.from(rate),
            IValue.optionalNull(),
            IValue.optionalNull(),
            IValue.from("cpu"),
            IValue.from(-1L),
            IValue.from(false),
            IValue.from(zeros),
            IValue.optionalNull(),
        )

        val output = LiteModuleLoader.load(store.model.absolutePath).useLite { model ->
            if (token != generation.get()) throw InterruptedException("Cancelled")
            model.forward(*args).toTuple()[0].toTensor().dataAsFloatArray
        }
        if (token != generation.get()) throw InterruptedException("Cancelled")
        require(output.size in 2400..(24000 * 45)) {
            "Unexpected Silero PCM size: " + output.size
        }
        val pcm = ShortArray(output.size) { i ->
            (output[i].coerceIn(-1f, 1f) * 32767f).toInt()
                .coerceIn(-32768, 32767).toShort()
        }
        playPcm(pcm, token)
        return output.size
    }

    private inline fun <T> org.pytorch.Module.useLite(block: (org.pytorch.Module) -> T): T {
        return try { block(this) } finally { destroy() }
    }

    private fun playPcm(samples: ShortArray, token: Int) {
        val sampleRate = 24000
        val channels = AudioFormat.CHANNEL_OUT_MONO
        val format = AudioFormat.ENCODING_PCM_16BIT
        val bytes = AudioTrack.getMinBufferSize(sampleRate, channels, format)
        check(bytes > 0) { "Invalid Android PCM output buffer" }
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(format)
                    .setChannelMask(channels)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(bytes, 16384))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        try {
            check(track.state == AudioTrack.STATE_INITIALIZED)
            synchronized(audioLock) {
                if (token != generation.get()) return
                currentTrack = track
                track.play()
            }
            var offset = 0
            while (offset < samples.size && generation.get() == token) {
                val amount = minOf(2048, samples.size - offset)
                val result = synchronized(audioLock) {
                    if (generation.get() != token) 0
                    else track.write(samples, offset, amount, AudioTrack.WRITE_BLOCKING)
                }
                if (result <= 0) {
                    if (generation.get() == token) error("AudioTrack write: $result")
                    break
                }
                offset += result
            }
            val limit = SystemClock.elapsedRealtime() + 12000L
            while (generation.get() == token &&
                track.playbackHeadPosition < offset &&
                SystemClock.elapsedRealtime() < limit) {
                Thread.sleep(15)
            }
        } finally {
            synchronized(audioLock) {
                if (currentTrack === track) currentTrack = null
                runCatching { track.pause() }
                runCatching { track.flush() }
                runCatching { track.stop() }
                runCatching { track.release() }
            }
        }
    }
}
