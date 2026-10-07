package com.dreampulse.assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import org.pytorch.IValue
import org.pytorch.LiteModuleLoader
import org.pytorch.LitePyTorchAndroid
import org.pytorch.Tensor
import org.pytorch.executorch.EValue
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Private local speech engine for Dream Pulse.
 *
 * This is NOT an Android TextToSpeechService. It accepts text only through the
 * in-process Flutter MethodChannel owned by Dream Pulse, so other apps cannot
 * submit passwords, clipboard contents, card numbers or arbitrary text to it.
 *
 * Neural weights: Silero TTS v5_5_ru. Exposed speakers: Baya and Kseniya only.
 */
class DreamPulseVoiceEngine(private val context: Context) {
    companion object {
        private const val SAMPLE_RATE = 48000
        private const val MODEL_DIR = "silero"
        private const val SYMBOLS = "_~|!+,-.:;?абвгдежзийклмнопрстуфхцчшщъыьэюяё–… "
        private const val SOS = '|'
        private const val EOS = '~'
        private val VOWELS = "аоуыэиеяёю".toSet()
        private val WORD_RE = Regex("[а-яё]+", RegexOption.IGNORE_CASE)
        private val NUMBER_RE = Regex("\\d{1,12}")
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val generation = AtomicInteger(0)

    @Volatile private var mel: org.pytorch.Module? = null
    @Volatile private var head: org.pytorch.Module? = null
    @Volatile private var accentor: org.pytorch.Module? = null
    @Volatile private var backbone: org.pytorch.executorch.Module? = null
    @Volatile private var currentTrack: AudioTrack? = null

    private val symbolToId = SYMBOLS.mapIndexed { i, c -> c to i }.toMap()
    private val threads = min(4, max(2, Runtime.getRuntime().availableProcessors() / 2))

    private val installedModelDir: File
        get() = File(context.filesDir, "dream-pulse-voice/model")

    fun modelPresent(): Boolean {
        val dir = installedModelDir
        return listOf("tts_mel.ptl", "head.ptl", "accentor.ptl", "backbone.pte")
            .all { File(dir, it).let { f -> f.isFile && f.length() > 1024L } }
    }

    fun warmup(done: (Result<Unit>) -> Unit) {
        executor.execute {
            done(runCatching {
                ensureLoaded()
                // Run only the light accentor on warmup. Full synthesis stays lazy.
                accentWords(listOf("привет"))
                Unit
            })
        }
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
            done(runCatching {
                ensureLoaded()
                val speaker = when (voice.lowercase(Locale.ROOT)) {
                    "kseniya" -> 2
                    else -> 1 // Baya
                }
                val chunks = chunks(normalize(text))
                for ((index, chunk) in chunks.withIndex()) {
                    if (token != generation.get()) break
                    val accented = accent(chunk)
                    if (accented.isBlank()) continue
                    val audio = synthesize(
                        accented,
                        speaker,
                        rate.coerceIn(0.70f, 1.40f),
                        pitch.coerceIn(0.80f, 1.20f),
                    )
                    applyTimbre(audio, timbre.coerceIn(-1f, 1f))
                    applyGain(audio, volume.coerceIn(0.40f, 1.60f))
                    play(audio, token)
                    if (index + 1 < chunks.size && token == generation.get()) {
                        sleepInterruptible(sentencePauseMs.coerceIn(0, 700), token)
                    }
                }
            })
        }
    }

    fun stop() {
        generation.incrementAndGet()
        stopTrack()
    }

    fun dispose() {
        stop()
        executor.shutdownNow()
        runCatching { mel?.destroy() }
        runCatching { head?.destroy() }
        runCatching { accentor?.destroy() }
        runCatching { backbone?.destroy() }
        mel = null
        head = null
        accentor = null
        backbone = null
    }

    @Synchronized
    private fun ensureLoaded() {
        if (mel != null && head != null && accentor != null && backbone != null) return
        check(modelPresent()) { "Silero model assets are missing" }

        LitePyTorchAndroid.setNumThreads(threads)
        val dir = installedModelDir
        accentor = LiteModuleLoader.load(File(dir, "accentor.ptl").absolutePath)
        mel = LiteModuleLoader.load(File(dir, "tts_mel.ptl").absolutePath)
        head = LiteModuleLoader.load(File(dir, "head.ptl").absolutePath)

        val backboneFile = File(dir, "backbone.pte")
        backbone = org.pytorch.executorch.Module.load(
            backboneFile.absolutePath,
            org.pytorch.executorch.Module.LOAD_MODE_MMAP,
            threads,
        )
    }

    private fun synthesize(
        accented: String,
        speakerId: Int,
        rate: Float,
        pitch: Float,
    ): FloatArray {
        val seq = sequence(accented)
        check(seq.size >= 3) { "Nothing to synthesize" }
        val n = seq.size.toLong()

        // v5_5_ru supports per-symbol duration and pitch coefficients.
        val rates = FloatArray(seq.size) { rate }
        val pitches = FloatArray(seq.size) { pitch }
        val type = when {
            accented.trimEnd().endsWith("?") -> 2L // general question
            accented.trimEnd().endsWith("!") -> 5L // exclamation
            else -> 0L
        }
        val typeIds = LongArray(seq.size) { type }

        val args = arrayListOf(
            IValue.from(Tensor.fromBlob(seq, longArrayOf(1, n))),
            IValue.from(
                Tensor.fromBlob(
                    longArrayOf(speakerId.toLong()),
                    longArrayOf(1),
                ),
            ),
            IValue.from(SAMPLE_RATE.toLong()),
            IValue.optionalNull(),
            IValue.from(Tensor.fromBlob(rates, longArrayOf(1, n))),
            IValue.from(Tensor.fromBlob(pitches, longArrayOf(1, n))),
            IValue.optionalNull(),
            IValue.optionalNull(),
            IValue.from("cpu"),
            IValue.from(-1L),
            IValue.from(false),
            IValue.from(Tensor.fromBlob(typeIds, longArrayOf(1, n))),
            IValue.optionalNull(),
        )

        val melOut = mel!!.forward(*args.toTypedArray()).toTuple()[0].toTensor()
        val etInput = org.pytorch.executorch.Tensor.fromBlob(
            melOut.dataAsFloatArray,
            melOut.shape(),
        )
        val hidden = backbone!!.forward(EValue.from(etInput))[0].toTensor()
        return head!!.forward(
            IValue.from(
                Tensor.fromBlob(
                    hidden.dataAsFloatArray,
                    hidden.shape(),
                ),
            ),
            IValue.from(SAMPLE_RATE.toLong()),
            IValue.from(0.0),
            IValue.from(true),
        ).toTensor().dataAsFloatArray
    }

    private fun accent(text: String): String {
        val matches = WORD_RE.findAll(text).toList()
        if (matches.isEmpty()) return text

        val clean = matches.map { it.value.lowercase(Locale.ROOT) }
        val neural = clean.mapIndexedNotNull { i, word ->
            val vowels = word.count { it in VOWELS }
            if (vowels > 1 && 'ё' !in word) i to word else null
        }
        val predictions = if (neural.isEmpty()) {
            emptyMap()
        } else {
            val probs = accentWords(neural.map { it.second })
            neural.mapIndexed { i, pair -> pair.first to probs[i] }.toMap()
        }

        val out = StringBuilder()
        var from = 0
        for ((index, match) in matches.withIndex()) {
            out.append(text.substring(from, match.range.first))
            val raw = match.value
            val lower = raw.lowercase(Locale.ROOT)
            val vowelPositions = lower.indices.filter { lower[it] in VOWELS }
            val stressedAt = when {
                vowelPositions.isEmpty() -> -1
                'ё' in lower -> lower.indexOf('ё')
                vowelPositions.size == 1 -> vowelPositions.first()
                else -> {
                    val row = predictions[index] ?: FloatArray(0)
                    var best = 0
                    var bestValue = Float.NEGATIVE_INFINITY
                    for (i in 0 until min(vowelPositions.size, row.size)) {
                        if (row[i] > bestValue) {
                            bestValue = row[i]
                            best = i
                        }
                    }
                    vowelPositions[best.coerceIn(0, vowelPositions.lastIndex)]
                }
            }
            if (stressedAt >= 0) {
                out.append(raw.substring(0, stressedAt))
                out.append('+')
                out.append(raw.substring(stressedAt))
            } else {
                out.append(raw)
            }
            from = match.range.last + 1
        }
        out.append(text.substring(from))
        return out.toString()
    }

    private fun accentWords(words: List<String>): List<FloatArray> {
        if (words.isEmpty()) return emptyList()
        val inputs = words.map { IValue.from(it) }.toTypedArray()
        val tuple = accentor!!.forward(IValue.listFrom(*inputs)).toTuple()
        val tensor = tuple[0].toTensor()
        val shape = tensor.shape()
        if (shape.size < 2) return words.map { FloatArray(0) }
        val rows = shape[0].toInt()
        val cols = shape[1].toInt()
        val data = tensor.dataAsFloatArray
        return List(min(rows, words.size)) { row ->
            FloatArray(cols) { col -> data[row * cols + col] }
        } + List(max(0, words.size - rows)) { FloatArray(0) }
    }

    private fun sequence(text: String): LongArray {
        val out = ArrayList<Long>(text.length + 2)
        out += symbolToId.getValue(SOS).toLong()
        for (char in text.lowercase(Locale.ROOT)) {
            symbolToId[char]?.let { out += it.toLong() }
        }
        out += symbolToId.getValue(EOS).toLong()
        return out.toLongArray()
    }

    private fun normalize(raw: String): String {
        var text = raw
            .replace('—', '–')
            .replace('−', '-')
            .replace('’', ' ')
            .replace('“', ' ')
            .replace('”', ' ')
            .replace('«', ' ')
            .replace('»', ' ')

        text = NUMBER_RE.replace(text) { match ->
            numberToWords(match.value.toLongOrNull() ?: 0L)
        }

        text = transliterateLatin(text)
        text = text.lowercase(Locale.ROOT)
        text = text.replace(Regex("[^а-яё+!,.\\-.:;?–…\\s]"), " ")
        text = text.replace(Regex("\\s+"), " ").trim()
        return text
    }

    private fun chunks(text: String): List<String> {
        if (text.isBlank()) return emptyList()
        val sentences = text.split(Regex("(?<=[.!?…])\\s+"))
        val out = ArrayList<String>()
        for (sentence in sentences) {
            var rest = sentence.trim()
            while (rest.length > 220) {
                var cut = rest.lastIndexOf(' ', 220)
                if (cut < 80) cut = 220
                out += rest.substring(0, cut).trim().ensureTail()
                rest = rest.substring(cut).trim()
            }
            if (rest.isNotEmpty()) out += rest.ensureTail()
        }
        return out
    }

    private fun String.ensureTail(): String {
        val t = trim()
        if (t.isEmpty()) return t
        return if (t.last() in ".!?…") t else "$t."
    }

    private fun applyGain(audio: FloatArray, gain: Float) {
        for (i in audio.indices) {
            audio[i] = (audio[i] * gain).coerceIn(-0.97f, 0.97f)
        }
    }

    /**
     * Lightweight colour control:
     *  timbre < 0 -> warmer / softer high frequencies
     *  timbre > 0 -> brighter / more present
     * This does not pretend to create a new neural speaker.
     */
    private fun applyTimbre(audio: FloatArray, timbre: Float) {
        if (audio.size < 2 || abs(timbre) < 0.01f) return
        if (timbre < 0f) {
            val amount = -timbre
            val alpha = 0.42f - amount * 0.24f
            var state = audio[0]
            for (i in 1 until audio.size) {
                state += alpha * (audio[i] - state)
                audio[i] = state
            }
        } else {
            val amount = 0.30f * timbre
            var prev = audio[0]
            for (i in 1 until audio.size) {
                val x = audio[i]
                audio[i] = (x + amount * (x - prev)).coerceIn(-0.97f, 0.97f)
                prev = x
            }
        }
    }

    private fun play(audio: FloatArray, token: Int) {
        if (audio.isEmpty() || token != generation.get()) return
        val pcm = ShortArray(audio.size) { i ->
            (audio[i].coerceIn(-0.97f, 0.97f) * 32767f).roundToInt().toShort()
        }
        val minBuffer = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(4096)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(minBuffer)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        currentTrack = track
        try {
            track.play()
            var offset = 0
            while (offset < pcm.size && token == generation.get()) {
                val count = min(4096, pcm.size - offset)
                val wrote = track.write(
                    pcm,
                    offset,
                    count,
                    AudioTrack.WRITE_BLOCKING,
                )
                if (wrote <= 0) break
                offset += wrote
            }
            while (
                token == generation.get() &&
                track.playState == AudioTrack.PLAYSTATE_PLAYING &&
                track.playbackHeadPosition < offset
            ) {
                Thread.sleep(12)
            }
        } finally {
            runCatching { track.stop() }
            runCatching { track.flush() }
            runCatching { track.release() }
            if (currentTrack === track) currentTrack = null
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

    private fun sleepInterruptible(ms: Int, token: Int) {
        var left = ms
        while (left > 0 && token == generation.get()) {
            val step = min(25, left)
            Thread.sleep(step.toLong())
            left -= step
        }
    }

    private fun transliterateLatin(input: String): String {
        val map = mapOf(
            'a' to "а", 'b' to "б", 'c' to "к", 'd' to "д", 'e' to "е",
            'f' to "ф", 'g' to "г", 'h' to "х", 'i' to "и", 'j' to "дж",
            'k' to "к", 'l' to "л", 'm' to "м", 'n' to "н", 'o' to "о",
            'p' to "п", 'q' to "к", 'r' to "р", 's' to "с", 't' to "т",
            'u' to "у", 'v' to "в", 'w' to "в", 'x' to "кс", 'y' to "й",
            'z' to "з",
        )
        val out = StringBuilder()
        for (char in input) {
            val low = char.lowercaseChar()
            val replacement = map[low]
            if (replacement == null) out.append(char) else out.append(replacement)
        }
        return out.toString()
    }

    private fun numberToWords(value: Long): String {
        if (value == 0L) return "ноль"
        if (value < 0L) return "минус " + numberToWords(-value)
        if (value > 999_999_999_999L) return value.toString()

        val groups = arrayOf(
            "" to arrayOf("", "", ""),
            "тысяча" to arrayOf("тысяча", "тысячи", "тысяч"),
            "миллион" to arrayOf("миллион", "миллиона", "миллионов"),
            "миллиард" to arrayOf("миллиард", "миллиарда", "миллиардов"),
        )
        var n = value
        var groupIndex = 0
        val parts = ArrayList<String>()
        while (n > 0) {
            val triad = (n % 1000).toInt()
            if (triad > 0) {
                val feminine = groupIndex == 1
                val words = triadWords(triad, feminine)
                val forms = groups[groupIndex].second
                val suffix = if (groupIndex == 0) "" else chooseForm(triad, forms)
                parts.add(0, listOf(words, suffix).filter { it.isNotBlank() }.joinToString(" "))
            }
            n /= 1000
            groupIndex++
        }
        return parts.joinToString(" ")
    }

    private fun triadWords(value: Int, feminine: Boolean): String {
        val hundreds = arrayOf(
            "", "сто", "двести", "триста", "четыреста",
            "пятьсот", "шестьсот", "семьсот", "восемьсот", "девятьсот",
        )
        val teens = arrayOf(
            "десять", "одиннадцать", "двенадцать", "тринадцать",
            "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать",
            "восемнадцать", "девятнадцать",
        )
        val tens = arrayOf(
            "", "", "двадцать", "тридцать", "сорок",
            "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто",
        )
        val unitsM = arrayOf(
            "", "один", "два", "три", "четыре",
            "пять", "шесть", "семь", "восемь", "девять",
        )
        val unitsF = arrayOf(
            "", "одна", "две", "три", "четыре",
            "пять", "шесть", "семь", "восемь", "девять",
        )

        val out = ArrayList<String>()
        out += hundreds[value / 100]
        val rest = value % 100
        if (rest in 10..19) {
            out += teens[rest - 10]
        } else {
            out += tens[rest / 10]
            out += (if (feminine) unitsF else unitsM)[rest % 10]
        }
        return out.filter { it.isNotBlank() }.joinToString(" ")
    }

    private fun chooseForm(value: Int, forms: Array<String>): String {
        val n100 = value % 100
        val n10 = value % 10
        return when {
            n100 in 11..14 -> forms[2]
            n10 == 1 -> forms[0]
            n10 in 2..4 -> forms[1]
            else -> forms[2]
        }
    }
}
