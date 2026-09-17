package com.sih.voicebridge.bridge

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper

import com.sih.voicebridge.download.NativeModelDownloadManager
import com.sih.voicebridge.location.LocationHelper
import com.sih.voicebridge.network.NetworkHelper
import com.sih.voicebridge.pipeline.VoicePipelineOrchestrator
import com.sih.voicebridge.connection.ConnectionRepository
import com.sih.voicebridge.connection.ConnectionRuntime

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class NativeBridgeHandler(
    context: Context,
    private val requestLocationPermission: ((MethodChannel.Result) -> Unit)? = null,
    canStartBackgroundConnection: () -> Boolean = { false },
    requestNotifications: ((MethodChannel.Result) -> Unit)? = null,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val appContext = context.applicationContext
    private val connectionCommands = ConnectionChannelHandler(appContext, canStartBackgroundConnection, requestNotifications)
    private val sharedEvents: (Map<String, Any?>) -> Unit = { event ->
        mainHandler.post { if (!disposed) eventSink?.success(event) }
    }

    private val locationHelperDelegate = lazy { LocationHelper(appContext) }
    private val locationHelper by locationHelperDelegate
    private val networkHelper by lazy { NetworkHelper(appContext) }

    private val mainHandler =
        Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var disposed = false

    // Download and storage calls must not construct the voice pipeline or bind TTS.
    private val orchestratorDelegate = lazy {
        VoicePipelineOrchestrator(appContext) { event ->

            /*
             * VoicePipelineOrchestrator can generate events from
             * background threads.
             *
             * Flutter EventChannel MUST receive events on the
             * Android main thread.
             */
            mainHandler.post {
                if (disposed) {
                    return@post
                }

                eventSink?.success(event)
            }
        }
    }
    private val orchestrator by orchestratorDelegate

    private val modelDownloads =
        ModelDownloadChannelHandler(NativeModelDownloadManager(appContext))

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (disposed) {
            result.error(
                "native_bridge_disposed",
                "Native bridge has already been disposed.",
                null,
            )
            return
        }

        try {
            if (connectionCommands.handle(call, result)) return
            if (modelDownloads.handle(call, result)) return

            when (call.method) {

                "initializePipelines" -> {

                    val languageCode =
                        call.argument<String>("languageCode")
                            ?: "en"

                    /*
                     * The orchestrator performs expensive initialization
                     * on its background executor.
                     */
                    orchestrator.initialize(languageCode)

                    /*
                     * Return immediately to Flutter.
                     */
                    result.success(null)
                }

                "setLanguage" -> {

                    val languageCode =
                        call.argument<String>("languageCode")
                            ?: "en"

                    orchestrator.setLanguage(languageCode)
                    ConnectionRuntime.worker.execute { ConnectionRepository.get(appContext).saveLanguage(languageCode) }

                    result.success(null)
                }

                "setOperationMode" -> {

                    val mode =
                        call.argument<String>("mode")
                            ?: "walkie_talkie"

                    orchestrator.setOperationMode(mode)

                    result.success(null)
                }

                "startListening" -> {

                    val ptt =
                        call.argument<Boolean>("ptt")
                            ?: true

                    val messageId =
                        call.argument<String>("messageId")

                    orchestrator.startListening(
                        ptt = ptt,
                        messageId = messageId,
                        pressedAtEpochMs =
                            call.argument<Number>(
                                "pressedAtEpochMs",
                            )?.toLong(),
                        requestedLanguage =
                            call.argument<String>(
                                "languageCode",
                            ),
                    )

                    result.success(null)
                }

                "stopListening" -> {

                    orchestrator.stopListening(
                        call.argument<String>("messageId"),
                    )

                    result.success(null)
                }

                "speakText" -> {

                    val text =
                        call.argument<String>("text")
                            ?: ""

                    val languageCode =
                        call.argument<String>("languageCode")
                            ?: "en"

                    val emergency =
                        call.argument<Boolean>("emergency")
                            ?: false

                    val messageId =
                        call.argument<String>("messageId")

                    orchestrator.speakText(
                        text = text,
                        languageCode = languageCode,
                        emergency = emergency,
                        messageId = messageId,
                    )

                    result.success(null)
                }

                "setEmergencyOverride" -> {

                    val enabled =
                        call.argument<Boolean>("enabled")
                            ?: false

                    orchestrator.setEmergencyOverride(
                        enabled,
                    )

                    result.success(null)
                }

                "setEmergencyVolumeBoost" -> {
                    orchestrator.setEmergencyVolumeBoost(call.argument<Boolean>("enabled") ?: true)
                    result.success(null)
                }

                "getPlaybackVolume", "setPlaybackVolume" -> {
                    val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    if (audio.isVolumeFixed || max <= 0) {
                        result.success(null)
                    } else {
                        if (call.method == "setPlaybackVolume") {
                            val percent = call.argument<Number>("percent")?.toDouble()
                                ?: throw IllegalArgumentException("percent is required")
                            require(percent.isFinite() && percent in 0.0..100.0)
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, (max * percent / 100).roundToInt(), 0)
                        }
                        result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100.0 / max)
                    }
                }

                /*
                 * ---------------------------------------------------------
                 * Application data directory
                 * ---------------------------------------------------------
                 */

                "getAppDataDirectory" -> {

                    result.success(
                        appContext
                            .filesDir
                            .absolutePath,
                    )
                }

                "getLocation" -> {
                    result.success(locationHelper.getCurrentLocation())
                }

                "hasLocationPermission" -> {
                    result.success(locationHelper.hasLocationPermission())
                }

                "requestLocationPermission" -> {
                    if (locationHelper.hasLocationPermission()) {
                        result.success(true)
                    } else if (requestLocationPermission != null) {
                        requestLocationPermission.invoke(result)
                    } else {
                        result.success(false)
                    }
                }

                "startLocationUpdates" -> {
                    locationHelper.startListening()
                    result.success(true)
                }

                "stopLocationUpdates" -> {
                    locationHelper.stopListening()
                    result.success(true)
                }

                "getWifiGatewayIp" -> {
                    result.success(networkHelper.getWifiGatewayIp())
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (error: Throwable) {

            result.error(
                "native_bridge_error",
                error.message
                    ?: error.javaClass.simpleName,
                null,
            )
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        if (disposed) {
            return
        }

        eventSink = events
        NativeEventHub.add(sharedEvents)
    }

    override fun onCancel(
        arguments: Any?,
    ) {
        /*
         * Cancel the Flutter event subscription,
         * but do not destroy the complete voice pipeline.
         */
        eventSink = null
        NativeEventHub.remove(sharedEvents)
    }

    fun dispose() {
        if (disposed) {
            return
        }

        disposed = true
        NativeEventHub.remove(sharedEvents)
        connectionCommands.dispose()

        /*
         * Stop location updates.
         */
        if (locationHelperDelegate.isInitialized()) locationHelper.stopListening()

        /*
         * Stop future events from reaching Flutter.
         */
        eventSink = null

        /*
         * Remove events that haven't executed yet.
         */
        mainHandler.removeCallbacksAndMessages(null)

        /*
         * Dispose native pipeline resources.
         */
        if (orchestratorDelegate.isInitialized()) orchestrator.dispose()
    }
}
