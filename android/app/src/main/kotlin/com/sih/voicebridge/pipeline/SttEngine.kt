package com.sih.voicebridge.pipeline

import android.content.Context

class SttEngine(
    context: Context,
    private val onStatus: (String) -> Unit = {},
) {
    private var languageCode: String = "en"
    private var activeSession: StreamingSttSession? = null

    private val fallbackBackend = FallbackSttBackend()
    private val sizeResolver = SttAssetResolver(context, onStatus)
    private val sherpaFactory = SherpaOnnxBackendFactory(context, onStatus)
    private var backend: StreamingSttBackend = fallbackBackend

    val backendName: String
        get() = backend.backendName
    val recognitionAvailable: Boolean
        get() = backend.recognitionAvailable

    fun currentModelSizeMb(): Double? {
        val sizedBackend = backend as? ModelSizedSttBackend
        val bytes = sizedBackend?.modelSizeBytes()
        if (bytes != null && bytes > 0L) {
            return bytes / (1024.0 * 1024.0)
        }

        val resolvedModel = sizeResolver.resolve(languageCode) ?: return null
        val resolvedBytes = listOf(
            resolvedModel.modelFile,
            resolvedModel.tokensFile,
            resolvedModel.encoderFile,
            resolvedModel.decoderFile,
            resolvedModel.joinerFile,
        ).sumOf { file ->
            if (file != null && file.exists()) {
                file.length()
            } else {
                0L
            }
        }

        if (resolvedBytes <= 0L) {
            return null
        }

        return resolvedBytes / (1024.0 * 1024.0)
    }

    fun activeModelName(code: String = languageCode): String {
        val resolved = sizeResolver.resolve(code)
        return when {
            resolved != null && resolved.type.equals("nemo_ctc", ignoreCase = true) ->
                "NeMo CTC int8 (${code.uppercase()})"
            resolved != null && resolved.type.equals("transducer", ignoreCase = true) ->
                "Sherpa Transducer (${code.uppercase()})"
            resolved != null ->
                "Sherpa STT (${code.uppercase()})"
            else ->
                "Offline STT (${code.uppercase()})"
        }
    }

    @Synchronized
    fun initialize(languageCode: String) {
        this.languageCode = languageCode
        selectBackend(languageCode)
    }

    @Synchronized
    fun setLanguage(languageCode: String) {
        this.languageCode = languageCode
        selectBackend(languageCode)
    }

    @Synchronized
    fun beginSession() {
        check(recognitionAvailable) { "STT unavailable for $languageCode; fallback transcripts are disabled" }
        resetSession()
        activeSession = backend.createSession(languageCode)
    }

    @Synchronized
    fun acceptAudio(samples: ShortArray, sampleRate: Int): SttResult {
        val session = activeSession ?: error("No active STT session to receive audio")
        val partial = session.acceptAudio(samples, sampleRate)
        return SttResult(partial = partial, finalText = null)
    }

    @Synchronized
    fun finalizeSession(): SttResult {
        val session = activeSession
        if (session == null) {
            return SttResult(partial = null, finalText = "")
        }

        return try {
            val text = session.finalizeText()
            SttResult(partial = null, finalText = text, metrics = session.metrics)
        } catch (error: Throwable) {
            SttResult(
                partial = null, finalText = null, metrics = session.metrics,
                error = error.message ?: error.javaClass.simpleName,
            )
        } finally {
            session.close()
            activeSession = null
        }
    }

    @Synchronized
    fun currentSessionMetrics(): Map<String, Any> = activeSession?.metrics.orEmpty()

    @Synchronized
    fun resetSession() {
        activeSession?.close()
        activeSession = null
    }

    @Synchronized
    fun shutdown() {
        resetSession()
        backend.close()
        backend = fallbackBackend
    }

    private fun selectBackend(languageCode: String) {
        resetSession()

        runCatching { backend.close() }.onFailure { onStatus("STT release failed: ${it.message}") }
        backend = fallbackBackend
        val nextBackend = sherpaFactory.createBackend(languageCode)
        if (nextBackend != null) {
            try {
                nextBackend.prepare()
                backend = nextBackend
            } catch (error: Throwable) {
                onStatus("STT preparation failed: ${error.message}")
                runCatching { nextBackend.close() }
            }
        }
        onStatus(if (recognitionAvailable) "STT ready: ${backend.backendName}"
            else "STT UNAVAILABLE: fallback mode flagged; no fabricated transcript will be emitted")
    }
}
