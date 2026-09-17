package com.sih.voicebridge.connection

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.sih.voicebridge.MainActivity
import com.sih.voicebridge.bridge.NativeEventHub
import com.sih.voicebridge.pipeline.SharedSpeechOutput
import java.util.concurrent.atomic.AtomicBoolean

class ConnectionForegroundService : Service() {
    companion object {
        const val ACTION_CONNECT = "com.sih.voicebridge.connection.CONNECT"
        const val ACTION_DISCONNECT = "com.sih.voicebridge.connection.DISCONNECT"
        const val EXTRA_GENERATION = "generation"
        private const val CHANNEL = "itantra_background_connection"
        private const val NOTIFICATION_ID = 7070
        private const val TAG = "BG_SERVICE"
    }
    private val main = Handler(Looper.getMainLooper())
    private lateinit var repository: ConnectionRepository
    private lateinit var speech: SharedSpeechOutput
    private var transport: NativeTcpConnection? = null
    private val stopping = AtomicBoolean(false)
    @Volatile private var token = -1L
    @Volatile private var state = "connecting"
    @Volatile private var peerCount = 0
    @Volatile private var foreground = false
    private var connectivity: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val speechEvents: (Map<String, Any?>) -> Unit = { event ->
        if (event["type"] in setOf("tts_started", "audio_started", "playback_finished", "error")) {
            ConnectionRuntime.worker.execute {
                runCatching { repository.playbackEvent(event) }
                    .onFailure { reportError("Could not update stored playback status") }
            }
            if (event["type"] == "tts_started") Log.i(TAG, "TTS started")
            if (event["type"] == "audio_started") Log.i(TAG, "TTS audio started")
        }
    }

    override fun onCreate() {
        super.onCreate()
        repository = ConnectionRepository.get(this)
        speech = SharedSpeechOutput.acquire(this)
        ConnectionRuntime.service = this
        NativeEventHub.add(speechEvents)
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(
                CHANNEL, "Background connection", NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Shows when iTantra maintains a local message connection" })
        }
        Log.i(TAG, "Starting")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISCONNECT) {
            Log.i(TAG, "User requested disconnect")
            stopping.set(true)
            transport?.stop()
            ConnectionRuntime.worker.execute {
                runCatching { repository.disconnect() }.onFailure { reportError("Could not save disconnect") }
                disconnectImmediately()
            }
            return START_NOT_STICKY
        }
        if (intent != null && intent.action != ACTION_CONNECT) { stopSelf(startId); return START_NOT_STICKY }
        val requestedToken = intent?.getLongExtra(EXTRA_GENERATION, -1L) ?: repository.generation()
        if (!repository.accepts(requestedToken)) {
            // Ignore a stale start intent without disturbing a newer valid connection.
            if (token < 0 || !repository.accepts(token)) stopSelf(startId)
            return if (repository.requested()) START_STICKY else START_NOT_STICKY
        }
        if (foreground && token == requestedToken && !stopping.get()) return START_STICKY
        token = requestedToken
        stopping.set(false)
        state = "connecting"
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(),
                if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING else 0)
            foreground = true
        } catch (_: Exception) {
            reportError("Android could not start the background connection. Open iTantra and try Connect again.")
            ConnectionRuntime.worker.execute {
                runCatching {
                    if (repository.accepts(requestedToken)) repository.disconnect()
                }.onFailure { reportError("Could not save disconnect") }
                disconnectImmediately()
            }
            return START_NOT_STICKY
        }
        ConnectionRuntime.pendingGeneration = null
        Log.i(TAG, "Foreground service active")
        transport?.close()
        transport = NativeTcpConnection(
            onState = ::updateState,
            onFrame = ::receive,
            onRetry = { Log.i(TAG, "Reconnecting in $it ms") },
        )
        transport!!.start(repository.config())
        registerNetworkObserver()
        ConnectionRuntime.publish(this)
        return START_STICKY
    }

    private fun updateState(next: String, peers: Int) {
        if (stopping.get() || !repository.accepts(token)) return
        state = next
        peerCount = peers
        Log.i(TAG, when (next) { "listening" -> "Server listening on 7070"; else -> next.replaceFirstChar { it.uppercase() } })
        val currentToken = token
        ConnectionRuntime.worker.execute {
            repository.saveState(currentToken, next)
            if (repository.accepts(currentToken) && !stopping.get()) ConnectionRuntime.publish(this)
        }
        main.post {
            if (foreground && !stopping.get()) runCatching {
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification())
            }
        }
    }

    private fun receive(frame: ByteArray): ByteArray? {
        if (stopping.get() || !repository.accepts(token)) return null
        val message = try { MessageWireCodec.decode(frame) } catch (_: Exception) {
            Log.w(TAG, "Dropped invalid message frame")
            return null
        }
        try {
            val record = repository.add(message, "remote") ?: return null
            Log.i(TAG, "Incoming message received")
            NativeEventHub.emit(mapOf("type" to "incoming_message", "record" to record))
            ConnectionRuntime.publish(this)
            if (!stopping.get() && repository.accepts(token)) {
                speech.speak(message.getString("message"), message.getString("language"),
                    message.getString("type") == "emergency", message.getString("id"))
            }
            return MessageWireCodec.encode(message)
        } catch (_: Exception) {
            reportError("Could not store incoming message")
            return null
        }
    }

    internal fun send(frame: ByteArray) {
        check(!stopping.get() && repository.accepts(token)) { "Connection is stopped" }
        val message = MessageWireCodec.decode(frame)
        val socketOwner = transport ?: error("Connection is not running")
        socketOwner.send(MessageWireCodec.encode(message))
        repository.add(message, "local")
    }

    internal fun snapshot(): Map<String, Any?> = mapOf("serviceRunning" to (foreground && !stopping.get()),
        "connected" to (state == "connected" && !stopping.get()),
        "state" to if (stopping.get()) "disconnected" else state, "peerCount" to peerCount)

    internal fun disconnectImmediately() {
        stopping.set(true)
        ConnectionRuntime.pendingGeneration = null
        transport?.stop()
        state = "disconnected"
        peerCount = 0
        ConnectionRuntime.publish(this)
        val stoppedToken = repository.generation()
        main.post {
            if (repository.generation() != stoppedToken && repository.requested()) return@post
            foreground = false
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun registerNetworkObserver() {
        if (networkCallback != null) return
        connectivity = getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onLost(network: Network) { if (!stopping.get()) transport?.networkChanged() }
            override fun onAvailable(network: Network) {
                if (!stopping.get() && state == "reconnecting") transport?.networkChanged()
            }
        }
        runCatching {
            connectivity?.registerNetworkCallback(NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), callback)
            networkCallback = callback
        }.onFailure { Log.w(TAG, "Network observer unavailable; socket retry remains active") }
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 7070, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 7071, Intent(this, ConnectionForegroundService::class.java)
            .setAction(ACTION_DISCONNECT), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val description = when (state) {
            "connected" -> "Connected • maintaining the local message connection"
            "listening" -> "Listening for messages on port 7070"
            "reconnecting" -> "Reconnecting to the local message network"
            else -> "Starting the local message connection"
        }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("iTantra connection active").setContentText(description)
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", stop).build()
    }

    private fun reportError(text: String) {
        Log.w(TAG, text)
        NativeEventHub.emit(mapOf("type" to "connection_error", "text" to text))
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "Task removed; requested connection remains active")
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopping.set(true)
        foreground = false
        transport?.close()
        networkCallback?.let { callback -> runCatching { connectivity?.unregisterNetworkCallback(callback) } }
        NativeEventHub.remove(speechEvents)
        speech.release()
        if (ConnectionRuntime.service === this) ConnectionRuntime.service = null
        ConnectionRuntime.publish(this)
        Log.i(TAG, "Service stopped")
        super.onDestroy()
    }
}
