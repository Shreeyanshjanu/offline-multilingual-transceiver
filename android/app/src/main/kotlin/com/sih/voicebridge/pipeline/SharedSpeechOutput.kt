package com.sih.voicebridge.pipeline

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.sih.voicebridge.bridge.NativeEventHub

/** One existing TtsEngine shared by the visible speech pipeline and connection service. */
internal class SharedSpeechOutput private constructor(context: Context) {
    companion object {
        private var instance: SharedSpeechOutput? = null
        @Synchronized fun acquire(context: Context): SharedSpeechOutput {
            val output = instance ?: SharedSpeechOutput(context.applicationContext).also { instance = it }
            output.owners++
            return output
        }
    }
    private var owners = 0
    private val main = Handler(Looper.getMainLooper())
    private val preferences = context.getSharedPreferences("itantra_audio", Context.MODE_PRIVATE)
    private val emergencyAudio = EmergencyAudioController(context)
    private var activeBoosts = 0
    @Volatile private var closed = false
    @Volatile var boostEnabled = preferences.getBoolean("emergency_volume_boost", true)
        private set
    val engine = TtsEngine(context, NativeEventHub::emit) {
        NativeEventHub.emit(mapOf("type" to "status", "text" to it))
    }

    fun speak(text: String, languageCode: String, emergency: Boolean, messageId: String,
              onPlaybackFinished: (() -> Unit)? = null) {
        main.post {
            if (closed) return@post
            val boosted = emergency && boostEnabled
            if (boosted) { activeBoosts++; emergencyAudio.prepareMaxVolume() }
            var completed = false
            val finish: () -> Unit = {
                main.post {
                    if (!completed) {
                        completed = true
                        if (boosted && --activeBoosts <= 0) emergencyAudio.restoreVolume()
                        NativeEventHub.emit(mapOf("type" to "playback_finished", "messageId" to messageId))
                        onPlaybackFinished?.invoke()
                    }
                }
            }
            try { engine.speak(text, languageCode, emergency, messageId, finish) }
            catch (_: Exception) {
                NativeEventHub.emit(mapOf("type" to "error", "messageId" to messageId,
                    "text" to "Native speech playback unavailable"))
                finish()
            }
        }
    }

    fun setBoost(enabled: Boolean) {
        boostEnabled = enabled
        preferences.edit().putBoolean("emergency_volume_boost", enabled).apply()
    }

    fun setOverride(enabled: Boolean) { main.post {
        if (enabled) emergencyAudio.prepareMaxVolume() else if (activeBoosts == 0) emergencyAudio.restoreVolume()
    } }

    fun release() = synchronized(Companion) {
        if (owners > 0 && --owners == 0) {
            closed = true
            instance = null
            main.post { engine.shutdown(); emergencyAudio.restoreVolume() }
        }
    }
}
