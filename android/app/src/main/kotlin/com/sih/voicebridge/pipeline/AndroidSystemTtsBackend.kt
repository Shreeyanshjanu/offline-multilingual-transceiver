package com.sih.voicebridge.pipeline

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

private enum class AndroidTtsInitState {
    INITIALIZING,
    READY,
    FAILED,
}

internal class AndroidSystemTtsBackend(
    private val context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit,
    private val emitStatus: (String) -> Unit,
    private val emitError: (String?, String) -> Unit,
) : TtsBackend {
    override val backendName: String = "android_tts"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingQueue = ArrayDeque<PendingTtsRequest>()
    // Android delivers utterance callbacks on Binder threads.
    private val activeByUtteranceId = ConcurrentHashMap<String, PendingTtsRequest>()

    private var initState = AndroidTtsInitState.INITIALIZING
    private var textToSpeech: TextToSpeech? = null

    init {
        mainHandler.post {
            initialize()
        }
    }

    override fun speak(request: PendingTtsRequest): Boolean {
        mainHandler.post {
            when (initState) {
                AndroidTtsInitState.READY -> speakInternal(request)
                AndroidTtsInitState.INITIALIZING -> pendingQueue.addLast(request)
                AndroidTtsInitState.FAILED -> {
                    emitError(request.messageId, "Android TextToSpeech unavailable")
                    request.onPlaybackFinished?.invoke()
                }
            }
        }
        return true
    }

    override fun shutdown() {
        mainHandler.post {
            for (request in activeByUtteranceId.values) {
                request.onPlaybackFinished?.invoke()
            }
            activeByUtteranceId.clear()

            while (pendingQueue.isNotEmpty()) {
                pendingQueue.removeFirst().onPlaybackFinished?.invoke()
            }

            textToSpeech?.stop()
            textToSpeech?.shutdown()
            textToSpeech = null
            initState = AndroidTtsInitState.FAILED
        }
    }

    private fun initialize() {
        if (textToSpeech != null) {
            return
        }

        textToSpeech = TextToSpeech(context) { status ->
            mainHandler.post {
                if (initState != AndroidTtsInitState.INITIALIZING) return@post
                if (status == TextToSpeech.SUCCESS) {
                    initState = AndroidTtsInitState.READY
                    textToSpeech?.setOnUtteranceProgressListener(progressListener())
                    emitStatus("Native Android TTS initialized")
                    flushPending()
                } else {
                    initState = AndroidTtsInitState.FAILED
                    emitError(null, "TTS initialization failed (status=$status)")
                    while (pendingQueue.isNotEmpty()) {
                        pendingQueue.removeFirst().onPlaybackFinished?.invoke()
                    }
                }
            }
        }
    }

    private fun flushPending() {
        while (pendingQueue.isNotEmpty()) {
            speakInternal(pendingQueue.removeFirst())
        }
    }

    private fun speakInternal(request: PendingTtsRequest) {
        val tts = textToSpeech
        if (tts == null || initState != AndroidTtsInitState.READY) {
            pendingQueue.addLast(request)
            return
        }

        val localeStatus = tts.setLanguage(localeForCode(request.languageCode))
        if (localeStatus == TextToSpeech.LANG_NOT_SUPPORTED ||
            localeStatus == TextToSpeech.LANG_MISSING_DATA
        ) {
            tts.setLanguage(Locale.US)
            emitStatus("TTS locale ${request.languageCode} unavailable, falling back to en-US")
        }

        // Background messages must never silently select a network-only voice.
        val effectiveLocale = if (localeStatus == TextToSpeech.LANG_NOT_SUPPORTED ||
            localeStatus == TextToSpeech.LANG_MISSING_DATA) Locale.US else localeForCode(request.languageCode)
        val offlineVoice = tts.voices?.filter {
            !it.isNetworkConnectionRequired && it.locale.language == effectiveLocale.language &&
                !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
        }?.maxByOrNull { it.quality }
        if (offlineVoice == null || tts.setVoice(offlineVoice) == TextToSpeech.ERROR) {
            emitError(request.messageId, "No installed offline TTS voice for ${effectiveLocale.language}")
            request.onPlaybackFinished?.invoke()
            return
        }

        emitEvent(
            mapOf(
                "type" to "tts_started",
                "text" to request.text,
                "languageCode" to request.languageCode,
                "messageId" to request.messageId,
                "emergency" to request.emergency,
                "backend" to backendName,
            ),
        )

        val utteranceId = "utt-${request.messageId}-${System.nanoTime()}"
        activeByUtteranceId[utteranceId] = request

        val params = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, if (request.emergency) 1.0f else 0.9f)
        }
        val queueMode = if (request.emergency) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD

        val result = tts.speak(request.text, queueMode, params, utteranceId)
        if (result == TextToSpeech.ERROR) {
            activeByUtteranceId.remove(utteranceId)
            emitError(request.messageId, "TTS speak() returned error")
            request.onPlaybackFinished?.invoke()
        }
    }

    private fun progressListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                val request = getRequest(utteranceId) ?: return
                emitEvent(
                    mapOf(
                        "type" to "audio_started",
                        "text" to request.text,
                        "messageId" to request.messageId,
                        "emergency" to request.emergency,
                        "backend" to backendName,
                    ),
                )
            }

            override fun onDone(utteranceId: String?) {
                removeRequest(utteranceId)?.onPlaybackFinished?.invoke()
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                if (interrupted) {
                    emitStatus("TTS playback interrupted")
                }
                removeRequest(utteranceId)?.onPlaybackFinished?.invoke()
            }

            override fun onError(utteranceId: String?) {
                val request = removeRequest(utteranceId)
                emitError(request?.messageId, "TTS playback error")
                request?.onPlaybackFinished?.invoke()
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                val request = removeRequest(utteranceId)
                emitError(request?.messageId, "TTS playback error code=$errorCode")
                request?.onPlaybackFinished?.invoke()
            }
        }
    }

    private fun getRequest(utteranceId: String?): PendingTtsRequest? {
        if (utteranceId.isNullOrBlank()) {
            return null
        }
        return activeByUtteranceId[utteranceId]
    }

    private fun removeRequest(utteranceId: String?): PendingTtsRequest? {
        if (utteranceId.isNullOrBlank()) {
            return null
        }
        return activeByUtteranceId.remove(utteranceId)
    }

    private fun localeForCode(languageCode: String): Locale {
        return when (languageCode.lowercase()) {
            "en" -> Locale.US
            "hi" -> Locale("hi", "IN")
            "gu" -> Locale("gu", "IN")
            "mr" -> Locale("mr", "IN")
            "kn" -> Locale("kn", "IN")
            "ml" -> Locale("ml", "IN")
            "ta" -> Locale("ta", "IN")
            "te" -> Locale("te", "IN")
            "bn" -> Locale("bn", "IN")
            "or" -> Locale("or", "IN")
            else -> Locale.forLanguageTag(languageCode)
        }
    }
}
