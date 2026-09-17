package com.sih.voicebridge.pipeline

import android.content.Context
import android.util.Log

class SherpaOnnxBackendFactory(
    private val context: Context,
    private val onStatus: (String) -> Unit,
) {
    private val assetResolver = SttAssetResolver(context, onStatus)
    private var classProbeDone = false
    private var sherpaAvailable = false
    private var reportedMissingLibrary = false

    // fun createBackend(languageCode: String): StreamingSttBackend? {
    //     if (!isSherpaAvailable()) {
    //         if (!reportedMissingLibrary) {
    //             onStatus("Sherpa-ONNX classes unavailable. Add Sherpa dependency, then restart app.")
    //             reportedMissingLibrary = true
    //         }
    //         return null
    //     }

    //     val model = assetResolver.resolve(languageCode)
    //     if (model == null) {
    //         onStatus("No usable STT model found for '$languageCode'. Falling back.")
    //         return null
    //     }

    //     return try {
    //         SherpaOnnxReflectiveBackend(context, model, onStatus)
    //     } catch (error: Throwable) {
    //         onStatus("Sherpa backend init failed: ${error.message}")
    //         null
    //     }
    // }

    fun createBackend(languageCode: String): StreamingSttBackend? {
        Log.e("SIH_STT", "========== STT BACKEND START ==========")
        Log.e("SIH_STT", "Language: $languageCode")

        if (!isSherpaAvailable()) {
            Log.e("SIH_STT", "❌ Sherpa classes NOT available")
            onStatus("STT: Sherpa classes unavailable")
            return null
        }

        Log.e("SIH_STT", "✅ Sherpa classes are available")

        val model = assetResolver.resolve(languageCode)

        if (model == null) {
            Log.e("SIH_STT", "❌ Model resolution FAILED for: $languageCode")
            onStatus("STT: Model resolution failed for $languageCode")
            return null
        }

        Log.e("SIH_STT", "✅ Model resolved")
        Log.e("SIH_STT", "Model path: ${model.modelFile.absolutePath}")
        Log.e("SIH_STT", "Model exists: ${model.modelFile.exists()}")
        Log.e("SIH_STT", "Model size: ${model.modelFile.length()} bytes")
        Log.e("SIH_STT", "Tokens path: ${model.tokensFile?.absolutePath}")
        Log.e("SIH_STT", "Tokens exists: ${model.tokensFile?.exists()}")

        return try {
            Log.e("SIH_STT", "Creating SherpaOnnxReflectiveBackend...")

            val backend = SherpaOnnxReflectiveBackend(
                context,
                model,
                onStatus,
            )

            Log.e("SIH_STT", "✅ Sherpa backend CREATED successfully")
            Log.e("SIH_STT", "========== STT BACKEND SUCCESS ==========")

            onStatus("STT backend active: ${backend.backendName}")

            backend
        } catch (error: Throwable) {
            Log.e(
                "SIH_STT",
                "❌ Sherpa backend creation FAILED",
                error,
            )

            onStatus(
                "STT backend failed: " +
                    "${error.javaClass.simpleName}: ${error.message}"
            )

            null
        }
    }

    private fun isSherpaAvailable(): Boolean {
        if (classProbeDone) {
            return sherpaAvailable
        }

        classProbeDone = true

        sherpaAvailable = try {
            Log.e("SIH_STT", "Checking Sherpa Java classes...")

            Class.forName(
                "com.k2fsa.sherpa.onnx.OfflineRecognizer"
            )

            Log.e(
                "SIH_STT",
                "✅ OfflineRecognizer found"
            )

            Class.forName(
                "com.k2fsa.sherpa.onnx.OfflineRecognizerConfig"
            )

            Log.e(
                "SIH_STT",
                "✅ OfflineRecognizerConfig found"
            )

            true
        } catch (error: Throwable) {
            Log.e(
                "SIH_STT",
                "❌ Sherpa class check FAILED",
                error,
            )

            false
        }

        return sherpaAvailable
    }
}
