package com.sih.voicebridge.pipeline

internal data class PendingTtsRequest(
    val text: String,
    val languageCode: String,
    val emergency: Boolean,
    val messageId: String,
    val onPlaybackFinished: (() -> Unit)?,
)

internal interface TtsBackend {
    val backendName: String

    fun speak(request: PendingTtsRequest): Boolean

    fun shutdown()
}
