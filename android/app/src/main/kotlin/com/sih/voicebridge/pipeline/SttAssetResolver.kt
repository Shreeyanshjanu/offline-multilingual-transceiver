package com.sih.voicebridge.pipeline

import android.content.Context
import org.json.JSONException
import org.json.JSONObject
import java.io.File

data class SttModelSpec(
    val languageCode: String,
    val type: String,
    val modelFileName: String,
    val tokensFileName: String?,
    val encoderFileName: String?,
    val decoderFileName: String?,
    val joinerFileName: String?,
)

data class ResolvedSttModel(
    val languageCode: String,
    val type: String,
    val modelFile: File,
    val tokensFile: File?,
    val encoderFile: File?,
    val decoderFile: File?,
    val joinerFile: File?,
)

class SttAssetResolver(
    private val context: Context,
    private val onStatus: (String) -> Unit,
) {
    companion object {
        private const val FLUTTER_ASSET_PREFIX = "flutter_assets/"
        private const val MANIFEST_RELATIVE_PATH =
            "assets/models/stt/model_manifest.json"
        private const val MODEL_ROOT_DIRECTORY = "stt_models"
    }

    private var manifestCache: Map<String, SttModelSpec>? = null
    private var manifestLoaded = false

    fun resolve(languageCode: String): ResolvedSttModel? {
        val manifest = loadManifest()

        if (manifest.isEmpty()) {
            return null
        }

        val languageKey = languageCode.lowercase()
        val spec = manifest[languageKey]

        if (spec == null) {
            onStatus(
                "No STT model spec found for '$languageCode' " +
                    "in model_manifest.json"
            )
            return null
        }

        val modelFile = resolveDownloadedModel(spec)

        if (modelFile == null) {
            onStatus(
                "STT model for '$languageCode' is not downloaded."
            )
            return null
        }

        val tokensFile = resolveDownloadedSharedFile(
            languageCode = languageKey,
            fileName = spec.tokensFileName,
        )

        if (spec.tokensFileName != null && tokensFile == null) {
            onStatus(
                "STT tokens for '$languageCode' are not downloaded."
            )
            return null
        }

        val encoderFile = resolveDownloadedLanguageFile(
            languageCode = languageKey,
            fileName = spec.encoderFileName,
        )

        val decoderFile = resolveDownloadedLanguageFile(
            languageCode = languageKey,
            fileName = spec.decoderFileName,
        )

        val joinerFile = resolveDownloadedLanguageFile(
            languageCode = languageKey,
            fileName = spec.joinerFileName,
        )

        return ResolvedSttModel(
            languageCode = spec.languageCode,
            type = spec.type,
            modelFile = modelFile,
            tokensFile = tokensFile,
            encoderFile = encoderFile,
            decoderFile = decoderFile,
            joinerFile = joinerFile,
        )
    }

    private fun loadManifest(): Map<String, SttModelSpec> {
        if (manifestLoaded) {
            return manifestCache.orEmpty()
        }

        manifestLoaded = true

        val manifestAssetPath =
            "$FLUTTER_ASSET_PREFIX$MANIFEST_RELATIVE_PATH"

        val payload = try {
            context.assets
                .open(manifestAssetPath)
                .bufferedReader()
                .use { it.readText() }
        } catch (error: Throwable) {
            onStatus(
                "STT manifest not found at " +
                    "$MANIFEST_RELATIVE_PATH: ${error.message}"
            )

            manifestCache = emptyMap()
            return manifestCache.orEmpty()
        }

        val parsed = try {
            parseManifest(payload)
        } catch (error: JSONException) {
            onStatus(
                "Invalid STT manifest JSON: ${error.message}"
            )
            emptyMap()
        }

        manifestCache = parsed
        return parsed
    }

    @Throws(JSONException::class)
    private fun parseManifest(
        payload: String,
    ): Map<String, SttModelSpec> {
        val root = JSONObject(payload)

        val languagesNode =
            if (root.has("languages")) {
                root.getJSONObject("languages")
            } else {
                root
            }

        val table = mutableMapOf<String, SttModelSpec>()
        val keys = languagesNode.keys()

        while (keys.hasNext()) {
            val languageCode = keys.next()
            val specNode =
                languagesNode.optJSONObject(languageCode)
                    ?: continue

            val spec =
                parseSpec(languageCode, specNode)
                    ?: continue

            table[languageCode.lowercase()] = spec
        }

        return table
    }

    private fun parseSpec(
        languageCode: String,
        node: JSONObject,
    ): SttModelSpec? {
        val modelFileName = pickFirstNonBlank(
            node.optString("modelFile", ""),
            node.optString("model", ""),
            node.optString("modelAsset", ""),
        )

        if (modelFileName.isNullOrBlank()) {
            return null
        }

        return SttModelSpec(
            languageCode = languageCode.lowercase(),
            type = pickFirstNonBlank(
                node.optString("type", ""),
                node.optString("modelType", ""),
            ) ?: "nemo_ctc",
            modelFileName = fileNameOnly(modelFileName),
            tokensFileName = pickOptionalFileName(
                node.optString("tokensFile", ""),
                node.optString("tokens", ""),
                node.optString("tokensAsset", ""),
            ),
            encoderFileName = pickOptionalFileName(
                node.optString("encoderFile", ""),
                node.optString("encoder", ""),
                node.optString("encoderAsset", ""),
            ),
            decoderFileName = pickOptionalFileName(
                node.optString("decoderFile", ""),
                node.optString("decoder", ""),
                node.optString("decoderAsset", ""),
            ),
            joinerFileName = pickOptionalFileName(
                node.optString("joinerFile", ""),
                node.optString("joiner", ""),
                node.optString("joinerAsset", ""),
            ),
        )
    }

    private fun resolveDownloadedModel(
        spec: SttModelSpec,
    ): File? {
        val languageDirectory = File(
            context.filesDir,
            "$MODEL_ROOT_DIRECTORY/${spec.languageCode}",
        )

        val modelFile = File(
            languageDirectory,
            spec.modelFileName,
        )

        return if (modelFile.exists() && modelFile.length() > 0L) {
            modelFile
        } else {
            null
        }
    }

    private fun resolveDownloadedSharedFile(
        languageCode: String,
        fileName: String?,
    ): File? {
        if (fileName.isNullOrBlank()) {
            return null
        }

        val rootDirectory = File(
            context.filesDir,
            MODEL_ROOT_DIRECTORY,
        )

        val file = File(rootDirectory, fileName)

        if (file.exists() && file.length() > 0L) {
            return file
        }

        if (languageCode != "en" &&
            fileName == "stt-indic-tokens.txt"
        ) {
            val sharedFile = File(
                rootDirectory,
                "stt-indic-tokens.txt",
            )

            if (sharedFile.exists() &&
                sharedFile.length() > 0L
            ) {
                return sharedFile
            }
        }

        return null
    }

    private fun resolveDownloadedLanguageFile(
        languageCode: String,
        fileName: String?,
    ): File? {
        if (fileName.isNullOrBlank()) {
            return null
        }

        val languageDirectory = File(
            context.filesDir,
            "$MODEL_ROOT_DIRECTORY/$languageCode",
        )

        val file = File(
            languageDirectory,
            fileName,
        )

        return if (file.exists() && file.length() > 0L) {
            file
        } else {
            null
        }
    }

    private fun fileNameOnly(path: String): String {
        return path
            .trim()
            .removePrefix("/")
            .substringAfterLast('/')
            .substringAfterLast('\\')
    }

    private fun pickOptionalFileName(
        vararg values: String?,
    ): String? {
        val value = pickFirstNonBlank(*values)
            ?: return null

        return fileNameOnly(value)
    }

    private fun pickFirstNonBlank(
        vararg values: String?,
    ): String? {
        for (value in values) {
            if (!value.isNullOrBlank()) {
                return value
            }
        }

        return null
    }
}
