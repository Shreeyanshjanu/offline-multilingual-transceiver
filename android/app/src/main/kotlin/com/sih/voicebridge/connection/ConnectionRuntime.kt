package com.sih.voicebridge.connection

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import com.sih.voicebridge.bridge.NativeEventHub
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Process-local access to the service; it never starts a connection during a status query. */
internal object ConnectionRuntime {
    val worker = Executors.newSingleThreadExecutor()
    @Volatile var service: ConnectionForegroundService? = null
    @Volatile var pendingGeneration: Long? = null
    private val revision = AtomicLong()

    fun status(context: Context): Map<String, Any?> {
        val version = revision.incrementAndGet()
        val repository = ConnectionRepository.get(context)
        val running = service?.snapshot() ?: mapOf("serviceRunning" to false, "connected" to false,
            "state" to "disconnected", "peerCount" to 0)
        val pending = pendingGeneration?.let(repository::accepts) == true
        return repository.status() + running + mapOf("startPending" to pending, "revision" to version,
            "notificationsAllowed" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "emergencyVolumeBoost" to context.getSharedPreferences("itantra_audio", Context.MODE_PRIVATE)
                .getBoolean("emergency_volume_boost", true))
    }

    fun publish(context: Context) = NativeEventHub.emit(mapOf("type" to "connection_state") + status(context))
}
