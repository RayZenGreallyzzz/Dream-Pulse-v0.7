package com.dreampulse.assistant

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.zip.ZipFile

/**
 * Installs an owner-provided Silero v5_5_ru model pack into Dream Pulse's own
 * app-private files. No system TTS, network connection or RuVoice app.
 *
 * IMPORTANT: This only validates/stages the original model weights. It does
 * not synthesize speech. A later PyTorch Lite + ExecuTorch backend must
 * explicitly implement inference before these weights become a playable voice.
 *
 * Internal hashes check pack integrity, NOT publisher authenticity.
 */
class DreamPulseSileroPackStore(private val context: Context) {
    companion object {
        private const val FORMAT = "dream-pulse-silero-base-v1"
        private const val MODEL = "v5_5_ru"
        private const val LICENSE = "CC BY-NC-SA 4.0"
        private const val MAX_PACK_BYTES = 450L * 1024L * 1024L
        private const val MAX_ENTRY_BYTES = 220L * 1024L * 1024L
        private val REQUIRED = setOf(
            "tts_mel.ptl",
            "head.ptl",
            "backbone.pte",
            "accentor.ptl",
            "homo.ptl",
            "stress.bin",
        )
        private val ALLOWED_SPEAKERS = setOf("baya", "kseniya", "xenia")
        private val HEX_SHA256 = Regex("^[0-9a-f]{64}$")
    }

    private val baseDir: File
        get() = File(context.filesDir, "dream-pulse-voice")
    private val installedDir: File
        get() = File(baseDir, "silero-v5_5_ru")

    fun status(): Map<String, Any> {
        val manifest = File(installedDir, "manifest.json")
        val filesPresent = REQUIRED.all { File(installedDir, it).isFile }
        return mapOf(
            "modelId" to MODEL,
            "modelStaged" to (manifest.isFile && filesPresent),
            "nativeRuntimeReady" to false,
            "canSynthesize" to false,
            "needsExternalTtsApp" to false,
            "message" to if (manifest.isFile && filesPresent) {
                "Веса Silero подготовлены. Нейронный рантайм ещё не подключён."
            } else {
                "Silero не установлен. Ирина продолжает работать отдельно."
            },
        )
    }

    @Synchronized
    fun install(archivePath: String): Map<String, Any> {
        val archive = File(archivePath)
        require(archive.isFile && archive.length() in 1..MAX_PACK_BYTES) {
            "Silero ZIP missing or too large"
        }
        val root = baseDir.apply { mkdirs() }
        val stage = File(root, ".silero-staging-" + System.nanoTime())
        if (!stage.mkdir()) throw IOException("Cannot create Silero staging directory")
        var backedUp: File? = null

        try {
            ZipFile(archive).use { zip ->
                val expectedEntries = REQUIRED.map { "silero/$it" }.toSet() +
                    "silero/manifest.json"
                val entries = zip.entries()
                val found = mutableSetOf<String>()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.isDirectory) {
                        require(entry.name == "silero/") {
                            "Unexpected directory in Silero pack: \${entry.name}"
                        }
                        continue
                    }
                    require(entry.name in expectedEntries && found.add(entry.name)) {
                        "Unexpected or duplicate Silero file: \${entry.name}"
                    }
                }
                require(found == expectedEntries) { "Silero ZIP is missing model files" }

                val manifestEntry = zip.getEntry("silero/manifest.json")
                    ?: throw IllegalArgumentException("Missing Silero manifest")
                val manifestBytes = zip.getInputStream(manifestEntry).use { input ->
                    // Never read an unbounded manifest into Android RAM.
                    val bytes = ByteArray(65_537)
                    val count = input.read(bytes)
                    require(count in 1..65_536 && input.read() == -1) {
                        "Silero manifest exceeds 64 KB"
                    }
                    bytes.copyOf(count)
                }
                val manifestText = manifestBytes.toString(Charsets.UTF_8)
                val json = JSONObject(manifestText)
                require(json.getString("format") == FORMAT)
                require(json.getString("model_id") == MODEL)
                require(json.getString("license") == LICENSE)
                require(json.optBoolean("non_commercial_only", false))
                require(!json.optBoolean("native_runtime_embedded", true))
                require(!json.optBoolean("user_recordings_trained", true))
                val speakers = json.getJSONArray("speaker_filter")
                val names = (0 until speakers.length())
                    .map { speakers.getString(it) }
                    .toSet()
                require(names == ALLOWED_SPEAKERS) {
                    "Only original female Silero speaker IDs may be staged"
                }

                val files = json.getJSONObject("files")
                require(files.length() == REQUIRED.size) {
                    "Silero manifest has unexpected files"
                }
                var total = 0L

                for (name in REQUIRED.sorted()) {
                    val fileInfo = files.getJSONObject(name)
                    val expectedSize = fileInfo.getLong("bytes")
                    val expectedHash = fileInfo.getString("sha256").lowercase()
                    require(expectedSize in 1..MAX_ENTRY_BYTES) {
                        "Invalid Silero module length: $name"
                    }
                    require(HEX_SHA256.matches(expectedHash)) {
                        "Invalid Silero SHA256: $name"
                    }
                    total += expectedSize
                    require(total <= MAX_PACK_BYTES) { "Silero model pack too large" }

                    val entry = zip.getEntry("silero/$name")
                        ?: throw IllegalArgumentException("Missing Silero $name")
                    if (entry.size != -1L) {
                        require(entry.size == expectedSize) {
                            "Silero entry length mismatch: $name"
                        }
                    }
                    val output = File(stage, name)
                    val digest = MessageDigest.getInstance("SHA-256")
                    var count = 0L
                    zip.getInputStream(entry).use { input ->
                        output.outputStream().buffered().use { destination ->
                            val buf = ByteArray(32 * 1024)
                            while (true) {
                                val n = input.read(buf)
                                if (n == -1) break
                                count += n
                                require(count <= expectedSize) {
                                    "Silero ZIP entry exceeded declared length: $name"
                                }
                                digest.update(buf, 0, n)
                                destination.write(buf, 0, n)
                            }
                        }
                    }
                    val actualHash = digest.digest()
                        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                    require(count == expectedSize && actualHash == expectedHash) {
                        "Silero module checksum mismatch: $name"
                    }
                }

                File(stage, "manifest.json").writeText(manifestText)
            }

            // The previous verified pack survives if staging/verification fails.
            if (installedDir.exists()) {
                val backup = File(root, ".silero-backup-" + System.nanoTime())
                if (!installedDir.renameTo(backup)) {
                    throw IOException("Unable to back up previous Silero model")
                }
                backedUp = backup
            }
            if (!stage.renameTo(installedDir)) {
                backedUp?.renameTo(installedDir)
                throw IOException("Unable to activate Silero model pack")
            }
            backedUp?.deleteRecursively()

            return status() + mapOf("installed" to true)
        } finally {
            if (stage.exists()) stage.deleteRecursively()
        }
    }
}
