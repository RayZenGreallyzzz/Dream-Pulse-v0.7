package com.dreampulse.assistant

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.zip.ZipFile

/** Verified, app-private TorchScript Lite pack, distinct from split .pte packs. */
class DreamPulseSileroLitePackStore(private val context: Context) {
    companion object {
        const val FORMAT = "dream-pulse-silero-full-lite-v1"
        private const val MAX_ZIP = 400L * 1024 * 1024
        private const val MAX_FILE = 350L * 1024 * 1024
        private val FILES = setOf("silero/model.ptl", "silero/symbols.json", "silero/manifest.json")
    }

    val dir: File get() = File(context.filesDir, "dream-pulse-voice/silero-full-lite")
    val model: File get() = File(dir, "model.ptl")
    val symbols: File get() = File(dir, "symbols.json")
    @Synchronized fun ready(): Boolean = File(dir, "manifest.json").isFile &&
        model.isFile && model.length() > 100_000 &&
        symbols.isFile && symbols.length() > 32

    fun status(): Map<String, Any> = mapOf(
        "basePreviewReady" to ready(),
        "modelStaged" to ready(),
        "nativeRuntimeReady" to true,
        "canSynthesize" to false, // User-created voices NOT trained.
        "message" to if (ready()) "Silero Lite готов к техническому тесту; авторские голоса ещё не обучены."
            else "Импортируй Silero Full Lite ZIP для технического синтеза.",
    )

    private fun readLimited(zip: ZipFile, name: String, max: Long): ByteArray {
        val entry = zip.getEntry(name) ?: error("Missing $name")
        require(entry.size in -1..max)
        return zip.getInputStream(entry).use { src ->
            val out = java.io.ByteArrayOutputStream()
            val buf = ByteArray(4096)
            while (true) {
                val n = src.read(buf)
                if (n < 0) break
                require(out.size().toLong() + n <= max) { "Oversize $name" }
                out.write(buf, 0, n)
            }
            out.toByteArray()
        }
    }

    @Synchronized fun install(path: String): Map<String, Any> {
        val archive = File(path)
        require(archive.isFile && archive.length() in 1..MAX_ZIP)
        val parent = dir.parentFile!!.apply { mkdirs() }
        val stage = File(parent, ".full-lite-stage-" + System.nanoTime())
        if (!stage.mkdir()) throw IOException("Cannot create model staging folder")
        var backup: File? = null
        try {
            ZipFile(archive).use { zip ->
                val found = mutableSetOf<String>()
                val entries = zip.entries()
                while (entries.hasMoreElements()) {
                    val e = entries.nextElement()
                    if (e.isDirectory) {
                        require(e.name == "silero/")
                    } else {
                        require(e.name in FILES && found.add(e.name)) {
                            "Unknown or duplicate entry: " + e.name
                        }
                    }
                }
                require(found == FILES) { "Missing Lite model files" }
                val manifestBytes = readLimited(zip, "silero/manifest.json", 65536L)
                val manifest = JSONObject(manifestBytes.toString(Charsets.UTF_8))
                require(manifest.getString("format") == FORMAT)
                require(manifest.getString("model_id") == "v5_5_ru")
                require(manifest.getString("license") == "CC BY-NC-SA 4.0")
                require(manifest.getBoolean("non_commercial_only"))
                require(manifest.getBoolean("silero_backend_test_only"))
                require(manifest.getJSONArray("public_voice_ids").length() == 0)
                require(manifest.getJSONArray("trained_user_voices").length() == 0)

                val symbolJson = JSONObject(
                    readLimited(zip, "silero/symbols.json", 2L * 1024 * 1024)
                        .toString(Charsets.UTF_8)
                )
                require(symbolJson.getInt("sample_rate") == 24000)
                require(symbolJson.getJSONObject("symbol_to_id").length() > 20)
                val speakers = symbolJson.getJSONObject("speakers")
                for (name in listOf("baya", "kseniya", "xenia")) require(speakers.has(name))

                val fileSpec = manifest.getJSONObject("files")
                require(fileSpec.length() == 2)
                for (name in listOf("model.ptl", "symbols.json")) {
                    val spec = fileSpec.getJSONObject(name)
                    val expectedSize = spec.getLong("bytes")
                    val expectedHash = spec.getString("sha256").lowercase()
                    require(expectedSize in 1..MAX_FILE)
                    require(Regex("^[0-9a-f]{64}$").matches(expectedHash))
                    val entry = zip.getEntry("silero/" + name) ?: error("Missing $name")
                    if (entry.size >= 0) require(entry.size == expectedSize)
                    val digest = MessageDigest.getInstance("SHA-256")
                    var read = 0L
                    zip.getInputStream(entry).use { src ->
                        File(stage, name).outputStream().buffered().use { dst ->
                            val buf = ByteArray(32768)
                            while (true) {
                                val n = src.read(buf)
                                if (n < 0) break
                                read += n
                                require(read <= expectedSize) { "Oversized $name" }
                                digest.update(buf, 0, n)
                                dst.write(buf, 0, n)
                            }
                        }
                    }
                    val actualHash = digest.digest().joinToString("") {
                        "%02x".format(it.toInt() and 0xff)
                    }
                    require(read == expectedSize && actualHash == expectedHash) {
                        "Corrupt model file: $name"
                    }
                }
                File(stage, "manifest.json").writeBytes(manifestBytes)
            }
            if (dir.exists()) {
                backup = File(parent, ".full-lite-backup-" + System.nanoTime())
                if (!dir.renameTo(backup)) throw IOException("Cannot back up existing model")
            }
            if (!stage.renameTo(dir)) {
                backup?.renameTo(dir)
                backup = null
                throw IOException("Cannot activate model")
            }
            backup?.deleteRecursively()
            backup = null
            return status() + mapOf("installed" to true)
        } catch (e: Throwable) {
            if (backup != null && backup!!.exists() && !dir.exists()) backup!!.renameTo(dir)
            throw e
        } finally {
            if (stage.exists()) stage.deleteRecursively()
        }
    }
}
