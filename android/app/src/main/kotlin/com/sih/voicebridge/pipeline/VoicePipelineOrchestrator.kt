package com.sih.voicebridge.pipeline

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.sih.voicebridge.bridge.NativeEventHub
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class VoicePipelineOrchestrator(
    context: Context,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) {
    private class CaptureRequest(
        val id: String,
        val ptt: Boolean,
        val pressedAtEpochMs: Long,
    ) {
        val stopRequested = AtomicBoolean(false)
        val failure = AtomicReference<String?>(null)
        val preRoll = AudioPreRoll()
        var languageCode = "en"
        var firstFrameSeen = false
        var firstFrameLatencyMs: Long? = null
        var utteranceActive = false
        var utteranceIndex = 0
        var utteranceStartMs: Long? = null
        var utteranceEndMs: Long? = null
        var deliveredSamples = 0L
        var decodeCalls = 0
        val messageId: String get() = if (utteranceIndex == 0) id else "$id-$utteranceIndex"
    }

    private val appContext = context.applicationContext
    private val audioCaptureManager = AudioCaptureManager()
    private val vadProcessor = VadProcessor()
    private val sttEngine = SttEngine(appContext, ::emitStatus)
    private val sentenceManager = SentenceManager()
    private val speechOutput = SharedSpeechOutput.acquire(appContext)
    private val ttsEngine = speechOutput.engine
    private val resourceMonitor = ResourceMonitor(appContext, emitEvent)
    private val pipelineExecutor = Executors.newSingleThreadExecutor()
    private val frameQueue = BoundedAudioFrameQueue(pipelineExecutor)
    private val captureRequest = AtomicReference<CaptureRequest?>(null)
    private val disposed = AtomicBoolean(false)
    private var initialized = false
    private var resourcesClosed = false
    private var languageCode = "en"
    private var mode = "walkie_talkie"
    private var pendingLanguage: String? = null
    private val playbackObserver: (Map<String, Any?>) -> Unit = { event ->
        when (event["type"]) {
            "tts_started" -> resourceMonitor.setPhase(ResourcePhase.TTS)
            "playback_finished" -> resourceMonitor.setPhase(ResourcePhase.IDLE)
        }
    }

    init { NativeEventHub.add(playbackObserver) }

    fun initialize(languageCode: String) {
        if (disposed.get()) return
        emitModelLoading(languageCode)
        pipelineExecutor.execute {
            if (disposed.get()) return@execute
            try {
                configureLanguage(languageCode)
                resourceMonitor.start()
                initialized = true
                emitStatus(if (sttEngine.recognitionAvailable) "Voice pipelines ready for $languageCode"
                    else "STT unavailable; typed communication and TTS remain available")
            } catch (error: Throwable) {
                emitModelReady(languageCode, error.message)
                emitError("Pipeline initialization failed: ${error.message}")
            }
        }
    }

    private fun emitModelLoading(code: String) {
        emitEvent(mapOf(
            "type" to "model_loading",
            "languageCode" to code,
            // Loading is emitted from the platform thread; resolve file-backed
            // model metadata only in emitModelReady on the pipeline executor.
            "sttModel" to "Offline STT (${code.uppercase()})",
            "ttsModel" to "Speech synthesis (${code.uppercase()})",
            "isLoading" to true,
            "estimatedSeconds" to 2,
            "message" to "Loading ${code.uppercase()} speech model... Please wait 1-2s",
        ))
    }

    private fun emitModelReady(code: String, errorMessage: String? = null) {
        val sttModel = if (sttEngine.recognitionAvailable && errorMessage == null) {
            sttEngine.activeModelName(code)
        } else {
            "Offline STT Unavailable"
        }
        val ttsModel = ttsEngine.activeEngineName(code)

        emitEvent(mapOf(
            "type" to "model_ready",
            "languageCode" to code,
            "sttModel" to sttModel,
            "ttsModel" to ttsModel,
            "sttAvailable" to (sttEngine.recognitionAvailable && errorMessage == null),
            "isLoading" to false,
            "message" to if (errorMessage == null) "Speech models active for ${code.uppercase()}"
                else "Speech model loading failed: $errorMessage",
        ))
    }

    private fun configureLanguage(code: String) {
        languageCode = code
        sttEngine.setLanguage(code)
        resourceMonitor.updateModelSizes(sttEngine.currentModelSizeMb(), ttsEngine.currentModelSizeMb(code))
        emitModelReady(code)
        emitEvent(mapOf(
            "type" to "stt_ready", "available" to sttEngine.recognitionAvailable,
            "fallback" to !sttEngine.recognitionAvailable, "languageCode" to code,
            "text" to if (sttEngine.recognitionAvailable) "STT ready for $code"
                else "STT UNAVAILABLE for $code; fallback transcripts are disabled",
        ))
    }

    fun setLanguage(languageCode: String) {
        if (disposed.get()) return
        emitModelLoading(languageCode)
        pipelineExecutor.execute {
            if (disposed.get()) return@execute
            if (captureRequest.get() != null) {
                pendingLanguage = languageCode
                emitStatus("Language change queued until recording finishes")
            } else {
                runCatching { configureLanguage(languageCode) }
                    .onFailure {
                        emitModelReady(languageCode, it.message)
                        emitError("Language switch failed: ${it.message}")
                    }
            }
        }
    }

    fun setOperationMode(mode: String) {
        if (disposed.get()) return
        pipelineExecutor.execute {
            this.mode = mode
            emitStatus("Operation mode set to $mode")
        }
    }

    fun startListening(
        ptt: Boolean,
        messageId: String?,
        pressedAtEpochMs: Long? = null,
        requestedLanguage: String? = null,
    ) {
        if (disposed.get()) return
        val capture = CaptureRequest(
            messageId ?: "native-${System.nanoTime()}", ptt,
            pressedAtEpochMs ?: System.currentTimeMillis(),
        )
        if (!captureRequest.compareAndSet(null, capture)) {
            emitError("Previous recording is still recording or finalizing", capture)
            return
        }
        pipelineExecutor.execute {
            try {
                if (disposed.get() || capture.stopRequested.get()) {
                    completeWithoutRecording(capture)
                    return@execute
                }
                check(initialized) { "Voice pipelines are still initializing" }
                check(hasRecordPermission()) { "RECORD_AUDIO permission not granted" }
                if (requestedLanguage != null && requestedLanguage != languageCode) configureLanguage(requestedLanguage)
                check(sttEngine.recognitionAvailable) { "STT unavailable; no fallback transcript will be sent" }
                capture.languageCode = languageCode
                vadProcessor.reset()
                if (capture.ptt) beginUtterance(capture)
                if (capture.stopRequested.get()) {
                    completeWithoutRecording(capture)
                    return@execute
                }
                resourceMonitor.setPhase(ResourcePhase.STT)
                audioCaptureManager.start(
                    stopRequested = capture.stopRequested,
                    onFrame = { frame ->
                        if (disposed.get() || capture.failure.get() != null) {
                            false
                        } else {
                            val accepted = frameQueue.offer(frame) { queuedFrame ->
                                if (!disposed.get() && capture.failure.get() == null) {
                                    try { handleAudioFrame(capture, queuedFrame) }
                                    catch (error: Throwable) { failCapture(capture, error.message ?: "Audio delivery failed") }
                                }
                            }
                            if (!accepted) failCapture(capture, "Audio queue exceeded 5 seconds; utterance discarded")
                            accepted
                        }
                    },
                    onError = { failure -> failCapture(capture, failure) },
                    onCompleted = { metrics ->
                        pipelineExecutor.execute { finishCapture(capture, metrics) }
                    },
                )
            } catch (error: Throwable) {
                failCapture(capture, error.message ?: error.javaClass.simpleName)
                completeWithoutRecording(capture)
            }
        }
    }

    fun stopListening(messageId: String? = null) {
        val capture = captureRequest.get() ?: return
        if (messageId == null || messageId == capture.id) capture.stopRequested.set(true)
    }

    private fun beginUtterance(capture: CaptureRequest) {
        sttEngine.beginSession()
        capture.utteranceActive = true
        capture.utteranceStartMs = null
        capture.utteranceEndMs = null
    }

    private fun handleAudioFrame(capture: CaptureRequest, frame: AudioFrame) {
        if (!capture.firstFrameSeen) {
            capture.firstFrameSeen = true
            capture.firstFrameLatencyMs = (frame.readAtEpochMs - capture.pressedAtEpochMs).coerceAtLeast(0)
            emitEvent(mapOf(
                "type" to "capture_state", "state" to "recording", "captureId" to capture.id,
                "messageId" to capture.id, "timestampEpochMs" to frame.timestampMs,
                "firstFrameLatencyMs" to capture.firstFrameLatencyMs,
                "text" to "Listening ($mode); microphone frames are arriving",
            ))
        }
        val decision = vadProcessor.process(frame)
        if (capture.ptt) {
            deliverAudio(capture, frame)
            return
        }
        if (!capture.utteranceActive) {
            capture.preRoll.add(frame)
            if (decision.isSpeech) {
                beginUtterance(capture)
                for (bufferedFrame in capture.preRoll.drain()) deliverAudio(capture, bufferedFrame)
            }
        } else {
            deliverAudio(capture, frame)
            if (decision.pauseDetected || decision.silenceDurationMs >= vadProcessor.silenceThresholdMs()) {
                finalizeUtterance(capture, "vad_pause")
                vadProcessor.reset()
            }
        }
    }

    private fun deliverAudio(capture: CaptureRequest, frame: AudioFrame) {
        sttEngine.acceptAudio(frame.samples, frame.sampleRate)
        capture.deliveredSamples += frame.samples.size
        if (capture.utteranceStartMs == null) capture.utteranceStartMs = frame.timestampMs
        capture.utteranceEndMs = frame.timestampMs + frame.samples.size * 1000L / frame.sampleRate
    }

    private fun finalizeUtterance(capture: CaptureRequest, reason: String) {
        if (!capture.utteranceActive) return
        val result = sttEngine.finalizeSession()
        capture.utteranceActive = false
        capture.decodeCalls += (result.metrics["decodeCalls"] as? Number)?.toInt() ?: 0
        val valid = result.error == null && capture.failure.get() == null && result.metrics["recognitionValid"] == true
        val metrics = result.metrics + mapOf(
            "type" to "stt_metrics", "messageId" to capture.messageId, "captureId" to capture.id,
            "backend" to sttEngine.backendName, "reason" to reason,
            "audioStartEpochMs" to capture.utteranceStartMs, "audioEndEpochMs" to capture.utteranceEndMs,
            "recognitionFinishedEpochMs" to System.currentTimeMillis(),
            "firstFrameLatencyMs" to capture.firstFrameLatencyMs, "recognitionValid" to valid,
            "error" to (result.error ?: capture.failure.get()),
        )
        logMetrics(metrics)
        if (result.error != null) failCapture(capture, result.error)
        val text = sentenceManager.finalizeSentence(result.finalText.orEmpty())
        if (valid && text.isNotBlank()) {
            emitEvent(mapOf(
                "type" to "final_sentence", "text" to text, "messageId" to capture.messageId,
                "captureId" to capture.id, "languageCode" to capture.languageCode,
                "reason" to reason, "recognitionValid" to true, "fallback" to false,
            ))
        }
        capture.utteranceIndex++
    }

    private fun failCapture(capture: CaptureRequest, reason: String) {
        capture.failure.compareAndSet(null, reason)
        capture.stopRequested.set(true)
    }

    private fun completeWithoutRecording(capture: CaptureRequest) {
        finishCapture(capture, mapOf("capturedSamples" to 0L, "capturedDurationMs" to 0.0))
    }

    private fun finishCapture(capture: CaptureRequest, captureMetrics: Map<String, Any?>) {
        try {
            if (!disposed.get() && capture.failure.get() == null) {
                finalizeUtterance(capture, "manual_stop")
            } else if (capture.utteranceActive) {
                logMetrics(sttEngine.currentSessionMetrics() + mapOf(
                    "type" to "stt_metrics", "messageId" to capture.messageId, "captureId" to capture.id,
                    "recognitionValid" to false, "error" to capture.failure.get(),
                ))
            }
            sttEngine.resetSession()
            captureRequest.compareAndSet(capture, null)
            val capturedSamples = (captureMetrics["capturedSamples"] as? Number)?.toLong() ?: 0L
            logMetrics(captureMetrics + mapOf(
                "type" to "capture_metrics", "captureId" to capture.id, "messageId" to capture.id,
                "deliveredSamples" to capture.deliveredSamples, "decodeCalls" to capture.decodeCalls,
                "firstFrameLatencyMs" to capture.firstFrameLatencyMs,
                "idleSamplesNotTranscribed" to if (!capture.ptt && capture.failure.get() == null)
                    capturedSamples - capture.deliveredSamples else 0L,
                "captureValid" to (capture.failure.get() == null && !disposed.get()),
                "error" to capture.failure.get(),
            ))
            val failure = capture.failure.get()
            if (failure != null && !disposed.get()) emitError(failure, capture)
            emitEvent(mapOf(
                "type" to "capture_state", "state" to "stopped", "captureId" to capture.id,
                "messageId" to capture.id, "failed" to (failure != null),
                "text" to if (failure != null) "Recording failed: $failure" else "Recording finished",
            ))
        } finally {
            captureRequest.compareAndSet(capture, null)
            resourceMonitor.setPhase(ResourcePhase.IDLE)
            if (disposed.get()) {
                closeResources()
            } else {
                val requestedLanguage = pendingLanguage
                pendingLanguage = null
                if (requestedLanguage != null) {
                    runCatching { configureLanguage(requestedLanguage) }
                        .onFailure {
                            emitModelReady(requestedLanguage, it.message)
                            emitError("Language switch failed: ${it.message}")
                        }
                }
            }
        }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        captureRequest.get()?.stopRequested?.set(true)
        pipelineExecutor.execute {
            if (captureRequest.get() == null) closeResources()
        }
    }

    private fun closeResources() {
        if (resourcesClosed) return
        resourcesClosed = true
        runCatching { sttEngine.shutdown() }
        NativeEventHub.remove(playbackObserver)
        speechOutput.release()
        resourceMonitor.stop()
        audioCaptureManager.shutdown()
        pipelineExecutor.shutdown()
    }

    fun speakText(text: String, languageCode: String, emergency: Boolean, messageId: String?) {
        val resolvedMessageId = messageId ?: "tts-${System.currentTimeMillis()}"
        resourceMonitor.setPhase(ResourcePhase.TTS)
        speechOutput.speak(text, languageCode, emergency, resolvedMessageId) {
            resourceMonitor.setPhase(ResourcePhase.IDLE)
        }
    }

    fun setEmergencyOverride(enabled: Boolean) = speechOutput.setOverride(enabled)

    fun setEmergencyVolumeBoost(enabled: Boolean) = speechOutput.setBoost(enabled)

    private fun hasRecordPermission(): Boolean =
        appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun logMetrics(event: Map<String, Any?>) {
        Log.i("ITANTRA_STT", JSONObject(event).toString())
        emitEvent(event)
    }

    private fun emitStatus(text: String) { emitEvent(mapOf("type" to "status", "text" to text)) }

    private fun emitError(text: String, capture: CaptureRequest? = null) {
        emitEvent(mapOf(
            "type" to "error", "text" to text, "messageId" to capture?.id,
            "captureId" to capture?.id, "captureError" to (capture != null),
        ))
    }
}
