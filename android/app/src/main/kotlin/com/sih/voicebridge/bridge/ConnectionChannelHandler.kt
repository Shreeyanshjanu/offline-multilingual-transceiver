package com.sih.voicebridge.bridge

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.sih.voicebridge.connection.ConnectionConfig
import com.sih.voicebridge.connection.ConnectionForegroundService
import com.sih.voicebridge.connection.ConnectionRepository
import com.sih.voicebridge.connection.ConnectionRuntime
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

internal class ConnectionChannelHandler(
    private val context: Context,
    private val canStart: () -> Boolean,
    private val requestNotifications: ((MethodChannel.Result) -> Unit)?,
) {
    private val main = Handler(Looper.getMainLooper())
    private val repository = ConnectionRepository.get(context)
    private val sends = Executors.newCachedThreadPool()

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "requestConnectionNotifications" -> {
                if (!canStart()) result.success(false)
                else requestNotifications?.invoke(result) ?: result.success(false)
            }
            "openConnectionBatterySettings" -> {
                context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "getBackgroundConnectionStatus" -> work(result) { ConnectionRuntime.status(context) }
            "getBackgroundMessages" -> work(result) { repository.messages() }
            "acknowledgeBackgroundMessages" -> work(result) {
                repository.acknowledge(call.argument<List<String>>("ids")?.toSet() ?: emptySet())
                ConnectionRuntime.publish(context)
                null
            }
            "clearBackgroundMessages" -> work(result) { repository.clearMessages(); null }
            "setBackgroundConnectionEnabled" -> work(result) {
                val enabled = call.argument<Boolean>("enabled") ?: error("enabled is required")
                try { repository.setEnabled(enabled) }
                finally { if (!enabled) stopServiceConnection() }
                ConnectionRuntime.publish(context)
                ConnectionRuntime.status(context)
            }
            "startBackgroundConnection" -> {
                if (!canStart()) {
                    result.error("visible_action_required", "Open iTantra and tap Connect to start background mode.", null)
                    return true
                }
                val config = ConnectionConfig(call.argument<Boolean>("runAsServer") ?: true,
                    call.argument<String>("host")?.trim() ?: "", call.argument<Int>("port") ?: 7070)
                ConnectionRuntime.worker.execute {
                    try {
                        val existing = ConnectionRuntime.service
                        if (existing?.snapshot()?.get("serviceRunning") == true && repository.requested() && repository.config() == config) {
                            main.post { result.success(ConnectionRuntime.status(context)) }
                            return@execute
                        }
                        val token = repository.requestConnection(config)
                        repository.saveLanguage(call.argument<String>("languageCode") ?: "en")
                        ConnectionRuntime.pendingGeneration = token
                        main.post {
                            try {
                                check(canStart() && repository.accepts(token)) { "Connect was cancelled; tap Connect while iTantra is visible" }
                                ContextCompat.startForegroundService(context, Intent(context, ConnectionForegroundService::class.java)
                                    .setAction(ConnectionForegroundService.ACTION_CONNECT)
                                    .putExtra(ConnectionForegroundService.EXTRA_GENERATION, token))
                                result.success(ConnectionRuntime.status(context))
                            } catch (_: Exception) {
                                ConnectionRuntime.worker.execute {
                                    runCatching {
                                        if (repository.accepts(token)) repository.disconnect()
                                    }
                                    if (ConnectionRuntime.pendingGeneration == token) ConnectionRuntime.pendingGeneration = null
                                    ConnectionRuntime.publish(context)
                                    main.post { result.error("background_start_failed", "Android could not start the connection. Open iTantra and try again.", null) }
                                }
                            }
                        }
                    } catch (_: Exception) {
                        main.post { result.error("connection_storage_error", "Could not save background connection settings", null) }
                    }
                }
            }
            "stopBackgroundConnection" -> work(result) {
                try { repository.disconnect() }
                finally { stopServiceConnection() }
                ConnectionRuntime.publish(context)
                ConnectionRuntime.status(context)
            }
            "sendBackgroundMessage" -> {
                val raw = call.argument<Map<String, Any?>>("message") ?: error("message is required")
                val frame = JSONObject(raw).toString().toByteArray(Charsets.UTF_8)
                sends.execute {
                    try {
                        (ConnectionRuntime.service ?: error("No background connection")).send(frame)
                        main.post { result.success(null) }
                    } catch (_: Exception) {
                        main.post { result.error("native_send_failed", "No TCP peer connected or send failed", null) }
                    }
                }
            }
            else -> return false
        }
        return true
    }

    private fun stopServiceConnection() {
        ConnectionRuntime.pendingGeneration = null
        val service = ConnectionRuntime.service
        if (service != null) service.disconnectImmediately()
        else main.post {
            if (!repository.requested()) context.stopService(Intent(context, ConnectionForegroundService::class.java))
        }
    }

    private fun work(result: MethodChannel.Result, action: () -> Any?) {
        ConnectionRuntime.worker.execute {
            try { val value = action(); main.post { result.success(value) } }
            catch (_: Exception) { main.post { result.error("native_connection_error", "Could not update background connection", null) } }
        }
    }

    fun dispose() { sends.shutdown() }
}
