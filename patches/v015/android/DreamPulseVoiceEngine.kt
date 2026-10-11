package com.dreampulse.assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.k2fsa.sherpa.onnx.GenerationConfig
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class DreamPulseVoiceEngine(private val context: Context) {
    companion object {
        private const val VOICE_DIR = "dream-pulse-voice"
        private const val MODEL_DIR = "vits-piper-ru_RU-irina-medium"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val generation = AtomicInteger(0)

    @Volatile private var tts: OfflineTts? = null
    @Volatile private var currentTrack: AudioTrack? = null

    fun voiceDir(): File = File(context.filesDir, VOICE_DIR)
    private fun modelDir(): File = File(voiceDir(), MODEL_DIR)
    private fun stageFile(): File = File(voiceDir(), "last-stage.txt")

    private fun mark(stage: String) {
        runCatching {
            voiceDir().mkdirs()
            stageFile().writeText(stage)
        }
    }

    fun lastStage(): String = runCatching {
        if (stageFile().isFile) stageFile().readText().trim() else "idle"
    }.getOrDefault("unknown")

    fun modelPresent(): Boolean {
        val dir = modelDir()
        val model = File(dir, "ru_RU-irina-medium.onnx")
        val tokens = File(dir, "tokens.txt")
        val espeak = File(dir, "espeak-ng-data")
        return model.isFile &&
            model.length() > 1_000_000L &&
            tokens.isFile &&
            tokens.length() > 100L &&
            espeak.isDirectory &&
            (espeak.listFiles()?.isNotEmpty() == true)
    }

    fun speak(
        text: String,
        voice: String,
        rate: Float,
        pitch: Float,
        timbre: Float,
        volume: Float,
        sentencePauseMs: Int,
        done: (Result<Unit>) -> Unit,
    ) {
        val token = generation.incrementAndGet()
        stopTrack()

        executor.execute {
            done(
                runCatching {
                    ensureLoaded()
                    val chunks = chunks(text)
                    for ((index, chunk) in chunks.withIndex()) {
                        if (token != generation.get()) break
                        if (chunk.isBlank()) continue

                        val requestedPitch = pitch.coerceIn(0.80f, 1.20f)
                        val requestedRate = rate.coerceIn(0.70f, 1.40f)
                        val modelSpeed =
                            (requestedRate / requestedPitch)
                                .coerceIn(0.60f, 1.60f)

                        mark("tts_generate")
                        val audio = tts!!.generateWithConfig(
                            text = chunk,
                            config = GenerationConfig(
                                silenceScale =
                                    if (voice == "zoey") 0.16f else 0.20f,
                                speed = modelSpeed,
                                sid = 0,
                            ),
                        )

                        var samples = audio.samples
                        if (abs(requestedPitch - 1.0f) > 0.005f) {
                            samples =
                                resampleForPitch(samples, requestedPitch)
                        }

                        applyTimbre(
                            samples,
                            timbre.coerceIn(-1f, 1f),
                        )
                        applyGain(
                            samples,
                            volume.coerceIn(0.40f, 1.60f),
                        )

                        mark("pcm_ready")
                        play(samples, audio.sampleRate, token)

                        if (
                            index + 1 < chunks.size &&
                            token == generation.get()
                        ) {
                            sleepInterruptible(
                                sentencePauseMs.coerceIn(0, 700),
                                token,
                            )
                        }
                    }
                    mark("done")
                },
            )
        }
    }

    fun stop() {
        generation.incrementAndGet()
        stopTrack()
    }

    fun dispose() {
        stop()
        executor.shutdownNow()
        runCatching { tts?.release() }
        tts = null
    }

    @Synchronized
    private fun ensureLoaded() {
        if (tts != null) return
        check(modelPresent()) { "Dream Voice model is missing" }

        val dir = modelDir()
        mark("load_model")

        val vits = OfflineTtsVitsModelConfig(
            model = File(
                dir,
                "ru_RU-irina-medium.onnx",
            ).absolutePath,
            tokens = File(dir, "tokens.txt").absolutePath,
            dataDir = File(dir, "espeak-ng-data").absolutePath,
            noiseScale = 0.667f,
            noiseScaleW = 0.8f,
            lengthScale = 1.0f,
        )

        val modelConfig = OfflineTtsModelConfig(
            vits = vits,
            numThreads = 2,
            debug = false,
            provider = "cpu",
        )

        tts = OfflineTts(
            config = OfflineTtsConfig(
                model = modelConfig,
                maxNumSentences = 1,
                silenceScale = 0.18f,
            ),
        )

        mark("model_loaded")
    }

    private fun chunks(raw: String): List<String> {
        val text = raw
            .replace('—', '–')
            .replace(Regex("\\s+"), " ")
            .trim()

        if (text.isBlank()) return emptyList()

        val sentences =
            text.split(Regex("(?<=[.!?…])\\s+"))
        val out = ArrayList<String>()

        for (sentence in sentences) {
            var rest = sentence.trim()
            while (rest.length > 220) {
                var cut = rest.lastIndexOf(' ', 220)
                if (cut < 90) cut = 220
                out += rest.substring(0, cut).trim()
                rest = rest.substring(cut).trim()
            }
            if (rest.isNotEmpty()) out += rest
        }

        return out
    }

    private fun resampleForPitch(
        input: FloatArray,
        ratio: Float,
    ): FloatArray {
        if (
            input.size < 2 ||
            abs(ratio - 1.0f) < 0.005f
        ) {
            return input
        }

        val outputSize =
            max(2, (input.size / ratio).toInt())
        val output = FloatArray(outputSize)

        for (i in output.indices) {
            val source = i * ratio
            val left =
                source.toInt().coerceIn(0, input.lastIndex)
            val right = min(left + 1, input.lastIndex)
            val frac = source - left
            output[i] =
                input[left] * (1f - frac) +
                input[right] * frac
        }

        return output
    }

    private fun applyGain(
        audio: FloatArray,
        gain: Float,
    ) {
        for (i in audio.indices) {
            audio[i] =
                (audio[i] * gain).coerceIn(-0.97f, 0.97f)
        }
    }

    private fun applyTimbre(
        audio: FloatArray,
        timbre: Float,
    ) {
        if (
            audio.size < 2 ||
            abs(timbre) < 0.01f
        ) {
            return
        }

        if (timbre < 0f) {
            val amount = -timbre
            val alpha = 0.44f - amount * 0.24f
            var state = audio[0]
            for (i in 1 until audio.size) {
                state += alpha * (audio[i] - state)
                audio[i] = state
            }
        } else {
            val amount = 0.28f * timbre
            var prev = audio[0]
            for (i in 1 until audio.size) {
                val x = audio[i]
                audio[i] =
                    (x + amount * (x - prev))
                        .coerceIn(-0.97f, 0.97f)
                prev = x
            }
        }
    }

    private fun play(
        audio: FloatArray,
        sampleRate: Int,
        token: Int,
    ) {
        if (
            audio.isEmpty() ||
            token != generation.get()
        ) {
            return
        }

        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
        ).coerceAtLeast(16_384)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(
                        AudioAttributes.CONTENT_TYPE_SPEECH,
                    )
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(
                        AudioFormat.ENCODING_PCM_FLOAT,
                    )
                    .setSampleRate(sampleRate)
                    .setChannelMask(
                        AudioFormat.CHANNEL_OUT_MONO,
                    )
                    .build(),
            )
            .setBufferSizeInBytes(minBuffer)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        currentTrack = track

        try {
            mark("audio_play")
            track.play()

            var offset = 0
            while (
                offset < audio.size &&
                token == generation.get()
            ) {
                val count =
                    min(4096, audio.size - offset)
                val wrote = track.write(
                    audio,
                    offset,
                    count,
                    AudioTrack.WRITE_BLOCKING,
                )
                if (wrote <= 0) break
                offset += wrote
            }

            while (
                token == generation.get() &&
                track.playState ==
                    AudioTrack.PLAYSTATE_PLAYING &&
                track.playbackHeadPosition < offset
            ) {
                Thread.sleep(12)
            }
        } finally {
            runCatching { track.stop() }
            runCatching { track.flush() }
            runCatching { track.release() }
            if (currentTrack === track) {
                currentTrack = null
            }
        }
    }

    private fun stopTrack() {
        currentTrack?.let { track ->
            runCatching { track.pause() }
            runCatching { track.flush() }
            runCatching { track.stop() }
            runCatching { track.release() }
        }
        currentTrack = null
    }

    private fun sleepInterruptible(
        ms: Int,
        token: Int,
    ) {
        var left = ms
        while (
            left > 0 &&
            token == generation.get()
        ) {
            val step = min(25, left)
            Thread.sleep(step.toLong())
            left -= step
        }
    }
}
