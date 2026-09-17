package com.sih.voicebridge.pipeline

import android.content.Context
import java.io.File

class TtsEngine(
    context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val emitStatus: (String) -> Unit,
) {
    private val appContext = context.applicationContext
    private val modelResolver = TtsModelResolver(appContext, emitStatus)

    private val androidBackend = AndroidSystemTtsBackend(
        context = appContext,
        emitEvent = emitEvent,
        emitStatus = emitStatus,
        emitError = ::emitError,
    )

    private val piperBackend = PiperSherpaTtsBackend(
        modelResolver = modelResolver,
        emitEvent = emitEvent,
        emitStatus = emitStatus,
        emitError = ::emitError,
    )

    fun activeEngineName(languageCode: String): String {
        val model = modelResolver.resolve(languageCode)
        val piper = model?.backend?.lowercase() in setOf("piper_sherpa", "piper", "sherpa_piper")
        return if (piper && model?.modelFile?.isFile == true && model.tokensFile?.isFile == true) {
            "Piper / Sherpa (${languageCode.uppercase()})"
        } else {
            val locale = if (languageCode == "en") "en-US" else "$languageCode-IN"
            "Android System TTS ($locale)"
        }
    }

    fun currentModelSizeMb(languageCode: String): Double? {
        val model = modelResolver.resolve(languageCode) ?: return null
        val backend = model.backend.lowercase()
        if (backend != "piper_sherpa" && backend != "piper" && backend != "sherpa_piper") {
            return null
        }

        val files = listOf(
            model.modelFile,
            model.tokensFile,
            model.lexiconFile,
        )

        var bytes = 0L
        for (file in files) {
            if (file != null && file.exists()) {
                bytes += file.length()
            }
        }

        bytes += directorySize(model.dataDir)

        if (bytes <= 0L) {
            return null
        }

        return bytes / (1024.0 * 1024.0)
    }

    fun speak(
        text: String,
        languageCode: String,
        emergency: Boolean,
        messageId: String,
        onPlaybackFinished: (() -> Unit)? = null,
    ) {
        val request = PendingTtsRequest(
            text = text,
            languageCode = languageCode,
            emergency = emergency,
            messageId = messageId,
            onPlaybackFinished = onPlaybackFinished,
        )

        val backend = selectBackendFor(languageCode)
        val spoken = backend.speak(request)
        if (!spoken && backend !== androidBackend) {
            androidBackend.speak(request)
        }
    }

    fun shutdown() {
        piperBackend.shutdown()
        androidBackend.shutdown()
    }

    private fun selectBackendFor(languageCode: String): TtsBackend {
        val model = modelResolver.resolve(languageCode)
        val backend = model?.backend?.lowercase() ?: "android_tts"
        return when (backend) {
            "piper_sherpa", "piper", "sherpa_piper" -> piperBackend
            else -> androidBackend
        }
    }

    private fun emitError(messageId: String?, text: String) {
        emitEvent(
            mapOf(
                "type" to "error",
                "text" to text,
                "messageId" to messageId,
            ),
        )
    }

    private fun directorySize(directory: File?): Long {
        if (directory == null || !directory.exists()) {
            return 0L
        }
        if (!directory.isDirectory) {
            return directory.length()
        }

        var bytes = 0L
        val children = directory.listFiles() ?: return 0L
        for (child in children) {
            bytes += directorySize(child)
        }
        return bytes
    }
}
