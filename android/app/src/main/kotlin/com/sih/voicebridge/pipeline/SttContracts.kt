package com.sih.voicebridge.pipeline

data class SttResult(
    val partial: String?,
    val finalText: String?,
    val metrics: Map<String, Any> = emptyMap(),
    val error: String? = null,
)

interface StreamingSttSession {
    val metrics: Map<String, Any> get() = emptyMap()
    fun acceptAudio(samples: ShortArray, sampleRate: Int): String?
    fun finalizeText(): String
    fun close() {}
}

interface StreamingSttBackend {
    val backendName: String
    val recognitionAvailable: Boolean get() = true
    fun prepare() {}
    fun createSession(languageCode: String): StreamingSttSession
    fun close() {}
}

interface ModelSizedSttBackend {
    fun modelSizeBytes(): Long?
}

class FallbackSttBackend : StreamingSttBackend, ModelSizedSttBackend {
    override val backendName: String = "fallback_unavailable"
    override val recognitionAvailable = false

    override fun createSession(languageCode: String): StreamingSttSession {
        return FallbackSttSession(languageCode)
    }

    override fun modelSizeBytes(): Long? {
        return null
    }
}

class FallbackSttSession(
    private val languageCode: String,
) : StreamingSttSession {
    override val metrics: Map<String, Any> get() = mapOf(
        "fallback" to true, "recognitionValid" to false, "decodeCalls" to 0,
    )
    override fun acceptAudio(samples: ShortArray, sampleRate: Int): String? = null
    override fun finalizeText(): String = ""
}
