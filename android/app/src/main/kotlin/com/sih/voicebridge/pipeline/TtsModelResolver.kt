package com.sih.voicebridge.pipeline

import android.content.Context
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream

private data class TtsModelSpec(
    val languageCode: String,
    val backend: String,
    val modelAssetPath: String?,
    val tokensAssetPath: String?,
    val dataDirAssetPath: String?,
    val lexiconAssetPath: String?,
)

internal data class ResolvedTtsModel(
    val languageCode: String,
    val backend: String,
    val modelFile: File?,
    val tokensFile: File?,
    val dataDir: File?,
    val lexiconFile: File?,
)

internal class TtsModelResolver(
    private val context: Context,
    private val emitStatus: (String) -> Unit,
) {
    companion object {
        private const val FLUTTER_ASSET_PREFIX = "flutter_assets/"
        private const val MANIFEST_RELATIVE_PATH = "assets/models/tts/model_manifest.json"
    }

    private var loadedManifest: Map<String, TtsModelSpec> = emptyMap()
    private var manifestLoaded = false

    fun resolve(languageCode: String): ResolvedTtsModel? {
        val manifest = loadManifest()
        if (manifest.isEmpty()) {
            return null
        }

        val spec = manifest[languageCode.lowercase()] ?: return null
        return ResolvedTtsModel(
            languageCode = spec.languageCode,
            backend = spec.backend,
            modelFile = copyOptional(spec.modelAssetPath),
            tokensFile = copyOptional(spec.tokensAssetPath),
            dataDir = copyDirectoryOptional(spec.dataDirAssetPath),
            lexiconFile = copyOptional(spec.lexiconAssetPath),
        )
    }

    private fun loadManifest(): Map<String, TtsModelSpec> {
        if (manifestLoaded) {
            return loadedManifest
        }

        manifestLoaded = true

        val manifestPayload = try {
            context.assets.open("$FLUTTER_ASSET_PREFIX$MANIFEST_RELATIVE_PATH")
                .bufferedReader()
                .use { it.readText() }
        } catch (_: Throwable) {
            emitStatus("TTS manifest not found at $MANIFEST_RELATIVE_PATH. Using Android TTS fallback.")
            loadedManifest = emptyMap()
            return loadedManifest
        }

        loadedManifest = try {
            parseManifest(manifestPayload)
        } catch (error: JSONException) {
            emitStatus("Invalid TTS manifest JSON: ${error.message}")
            emptyMap()
        }

        return loadedManifest
    }

    @Throws(JSONException::class)
    private fun parseManifest(payload: String): Map<String, TtsModelSpec> {
        val root = JSONObject(payload)
        val languages = if (root.has("languages")) {
            root.getJSONObject("languages")
        } else {
            root
        }

        val table = mutableMapOf<String, TtsModelSpec>()
        val keys = languages.keys()
        while (keys.hasNext()) {
            val languageCode = keys.next()
            val node = languages.optJSONObject(languageCode) ?: continue

            table[languageCode.lowercase()] = TtsModelSpec(
                languageCode = languageCode.lowercase(),
                backend = node.optString("backend", "android_tts"),
                modelAssetPath = pickFirstNonBlank(node.optString("model", ""), node.optString("modelAsset", "")),
                tokensAssetPath = pickFirstNonBlank(node.optString("tokens", ""), node.optString("tokensAsset", "")),
                dataDirAssetPath = pickFirstNonBlank(node.optString("data", ""), node.optString("dataDir", "")),
                lexiconAssetPath = pickFirstNonBlank(node.optString("lexicon", ""), node.optString("lexiconAsset", "")),
            )
        }

        return table
    }

    private fun copyOptional(assetPath: String?): File? {
        if (assetPath.isNullOrBlank()) {
            return null
        }

        val normalized = assetPath.trim().removePrefix("/")
        val flutterAssetPath = "$FLUTTER_ASSET_PREFIX$normalized"
        val target = File(context.filesDir, "tts_models/$normalized")

        if (target.exists() && target.length() > 0L) {
            return target
        }

        return try {
            target.parentFile?.mkdirs()
            context.assets.open(flutterAssetPath).use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }
            target
        } catch (_: Throwable) {
            null
        }
    }

    private fun copyDirectoryOptional(assetPath: String?): File? {
        if (assetPath.isNullOrBlank()) {
            return null
        }

        val normalized = assetPath.trim().removePrefix("/").trimEnd('/')
        val flutterPrefix = "$FLUTTER_ASSET_PREFIX$normalized"
        val targetDir = File(context.filesDir, "tts_models/$normalized")
        targetDir.mkdirs()

        val children = try {
            context.assets.list(flutterPrefix)
        } catch (_: Throwable) {
            null
        } ?: return null

        for (child in children) {
            val childAssetPath = "$flutterPrefix/$child"
            val childFile = File(targetDir, child)
            if (childFile.exists() && childFile.length() > 0L) {
                continue
            }
            try {
                context.assets.open(childAssetPath).use { input ->
                    FileOutputStream(childFile).use { output ->
                        input.copyTo(output)
                    }
                }
            } catch (_: Throwable) {
                return null
            }
        }

        return targetDir
    }

    private fun pickFirstNonBlank(vararg values: String?): String? {
        for (value in values) {
            if (!value.isNullOrBlank()) {
                return value
            }
        }
        return null
    }
}
