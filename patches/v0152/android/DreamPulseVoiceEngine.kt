package com.dreampulse.assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.AudioManager
import com.k2fsa.sherpa.onnx.GenerationConfig
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.max

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

                        streamChunk(
                            text = chunk,
                            voice = voice,
                            rate = rate,
                            volume = volume,
                            token = token,
                        )

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
                }
            )
        }
    }

    fun diagnose(done: (Result<String>) -> Unit) {
        val token = generation.incrementAndGet()
        stopTrack()

        executor.execute {
            done(
                runCatching {
                    mark("diag_audio_start")
                    playDiagnosticTone(token)
                    check(token == generation.get()) {
                        "Diagnostic was cancelled"
                    }
                    mark("diag_audio_ok")

                    check(modelPresent()) {
                        "Voice model files are missing"
                    }
                    mark("diag_model_files_ok")

                    ensureLoaded()
                    val localTts = checkNotNull(tts)
                    val sampleRate = localTts.sampleRate()
                    check(sampleRate > 0) {
                        "Invalid TTS sample rate: $sampleRate"
                    }
                    mark("diag_model_ok")

                    var samplesSeen = 0L
                    mark("diag_tts_start")
                    val generated =
                        localTts.generateWithConfigAndCallback(
                            text = "Привет. Это проверка голоса Dream Pulse.",
                            config = GenerationConfig(
                                silenceScale = 0.2f,
                                speed = 1.0f,
                                sid = 0,
                            ),
                        ) { samples ->
                            samplesSeen += samples.size.toLong()
                            1
                        }

                    val total =
                        maxOf(samplesSeen, generated.samples.size.toLong())
                    check(total > 1000L) {
                        "TTS returned no audio samples"
                    }
                    mark("diag_tts_ok")

                    "AUDIO OK · MODEL OK · TTS OK · " +
                        "rate=$sampleRate · samples=$total"
                }
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

        check(modelPresent()) {
            "Dream Voice model is missing"
        }

        val dir = modelDir()

        mark("native_load")

        val vits = OfflineTtsVitsModelConfig(
            model = File(
                dir,
                "ru_RU-irina-medium.onnx",
            ).absolutePath,
            tokens = File(
                dir,
                "tokens.txt",
            ).absolutePath,
            dataDir = File(
                dir,
                "espeak-ng-data",
            ).absolutePath,
            noiseScale = 0.667f,
            noiseScaleW = 0.8f,
            lengthScale = 1.0f,
        )

        val modelConfig = OfflineTtsModelConfig(
            vits = vits,
            numThreads = 1,
            debug = false,
            provider = "cpu",
        )

        mark("model_create")

        tts = OfflineTts(
            config = OfflineTtsConfig(
                model = modelConfig,
                maxNumSentences = 1,
                silenceScale = 0.2f,
            ),
        )

        mark("model_loaded")
    }

    private fun streamChunk(
        text: String,
        voice: String,
        rate: Float,
        volume: Float,
        token: Int,
    ) {
        val localTts = checkNotNull(tts)
        val sampleRate = localTts.sampleRate()

        check(sampleRate > 0) {
            "Invalid sample rate: $sampleRate"
        }

        val track = createPcm16Track(sampleRate)
        currentTrack = track

        var totalWritten = 0L
        var sawAudio = false

        try {
            mark("audio_track_ready")
            track.play()

            val speed = rate.coerceIn(0.70f, 1.40f)
            val silence =
                if (voice == "zoey") 0.16f else 0.20f
            val gain = volume.coerceIn(0.40f, 1.60f)

            mark("tts_stream")

            val generated =
                localTts.generateWithConfigAndCallback(
                    text = text,
                    config = GenerationConfig(
                        silenceScale = silence,
                        speed = speed,
                        sid = 0,
                    ),
                ) { samples ->
                    if (token != generation.get()) {
                        return@generateWithConfigAndCallback 0
                    }

                    if (samples.isEmpty()) {
                        return@generateWithConfigAndCallback 1
                    }

                    if (!sawAudio) {
                        sawAudio = true
                        mark("audio_first_chunk")
                    }

                    val pcm = floatToPcm16(samples, gain)
                    val written = track.write(
                        pcm,
                        0,
                        pcm.size,
                        AudioTrack.WRITE_BLOCKING,
                    )

                    if (written <= 0) {
                        mark("audio_write_error:$written")
                        return@generateWithConfigAndCallback 0
                    }

                    totalWritten += written.toLong()
                    1
                }

            check(sawAudio || generated.samples.isNotEmpty()) {
                "TTS generated no audio"
            }

            mark("tts_generated")

            if (
                token == generation.get() &&
                track.playState == AudioTrack.PLAYSTATE_PLAYING
            ) {
                mark("audio_drain")
                val expected =
                    totalWritten.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()

                while (
                    token == generation.get() &&
                    track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                    track.playbackHeadPosition < expected
                ) {
                    Thread.sleep(10)
                }
            }
        } finally {
            releaseTrack(track)
        }
    }

    private fun createPcm16Track(sampleRate: Int): AudioTrack {
        val minBuffer = max(
            AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            ),
            16_384,
        )

        val track = AudioTrack(
            AudioAttributes.Builder()
                .setContentType(
                    AudioAttributes.CONTENT_TYPE_SPEECH,
                )
                .setUsage(
                    AudioAttributes.USAGE_MEDIA,
                )
                .build(),
            AudioFormat.Builder()
                .setEncoding(
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                .setChannelMask(
                    AudioFormat.CHANNEL_OUT_MONO,
                )
                .setSampleRate(sampleRate)
                .build(),
            minBuffer,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE,
        )

        check(track.state == AudioTrack.STATE_INITIALIZED) {
            "AudioTrack PCM16 initialization failed"
        }

        return track
    }

    private fun floatToPcm16(
        input: FloatArray,
        gain: Float,
    ): ShortArray {
        val out = ShortArray(input.size)

        for (i in input.indices) {
            val value =
                (input[i] * gain).coerceIn(-1.0f, 1.0f)

            out[i] =
                (value * 32767.0f).toInt().toShort()
        }

        return out
    }

    private fun playDiagnosticTone(token: Int) {
        val sampleRate = 24000
        val samples = ShortArray(sampleRate / 3)
        val amplitude = 0.22
        val frequency = 660.0

        for (i in samples.indices) {
            val value =
                sin(2.0 * PI * frequency * i / sampleRate)
            samples[i] =
                (value * amplitude * 32767.0).toInt().toShort()
        }

        val track = createPcm16Track(sampleRate)
        currentTrack = track

        try {
            track.play()
            val written = track.write(
                samples,
                0,
                samples.size,
                AudioTrack.WRITE_BLOCKING,
            )
            check(written > 0) {
                "Diagnostic AudioTrack write failed: $written"
            }

            while (
                token == generation.get() &&
                track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                track.playbackHeadPosition < written
            ) {
                Thread.sleep(10)
            }
        } finally {
            releaseTrack(track)
        }
    }

    private fun releaseTrack(track: AudioTrack) {
        runCatching { track.pause() }
        runCatching { track.flush() }
        runCatching { track.stop() }
        runCatching { track.release() }

        if (currentTrack === track) {
            currentTrack = null
        }
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

            if (rest.isNotEmpty()) {
                out += rest
            }
        }

        return out
    }

    private fun stopTrack() {
        currentTrack?.let { track ->
            releaseTrack(track)
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
            val step = minOf(25, left)
            Thread.sleep(step.toLong())
            left -= step
        }
    }
}
