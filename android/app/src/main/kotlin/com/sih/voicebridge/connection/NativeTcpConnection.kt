package com.sih.voicebridge.connection

import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Socket owner used only by ConnectionForegroundService. No Android/Flutter lifetime dependency. */
internal class NativeTcpConnection(
    private val onState: (String, Int) -> Unit,
    private val onFrame: (ByteArray) -> ByteArray?,
    private val onRetry: (Long) -> Unit = {},
) : AutoCloseable {
    private val lock = Any()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val io = Executors.newCachedThreadPool()
    private val peers = linkedSetOf<Socket>()
    private val backoff = ReconnectBackoff()
    private var server: ServerSocket? = null
    private var pending: Socket? = null
    private var retry: ScheduledFuture<*>? = null
    private var config: ConnectionConfig? = null
    private var requested = false
    private var closed = false
    private var epoch = 0L

    fun start(configuration: ConnectionConfig) = synchronized(lock) {
        check(!closed)
        config = configuration
        requested = true
        backoff.reset()
        scheduleLocked(0, "connecting")
    }

    fun networkChanged() = synchronized(lock) {
        if (requested && !closed) scheduleLocked(backoff.nextDelay(), "reconnecting")
    }

    private fun scheduleLocked(delayMs: Long, state: String) {
        epoch++
        val token = epoch
        retry?.cancel(false)
        closeSocketsLocked()
        onState(state, 0)
        if (delayMs > 0) onRetry(delayMs)
        retry = scheduler.schedule({
            synchronized(lock) {
                if (!valid(token)) return@schedule
                retry = null
            }
            io.execute { attempt(token) }
        }, delayMs, TimeUnit.MILLISECONDS)
    }

    private fun valid(token: Long) = requested && !closed && token == epoch

    private fun attempt(token: Long) {
        val settings = synchronized(lock) { if (valid(token)) config else null } ?: return
        try {
            if (settings.runAsServer) {
                val listener = ServerSocket()
                synchronized(lock) {
                    if (!valid(token)) { listener.close(); return }
                    server = listener
                }
                listener.reuseAddress = true
                listener.bind(InetSocketAddress(settings.port))
                synchronized(lock) { if (valid(token)) onState("listening", peers.size) }
                while (true) {
                    val peer = listener.accept()
                    if (attach(token, peer)) io.execute { readPeer(token, peer, true) }
                }
            } else {
                val socket = Socket()
                synchronized(lock) {
                    if (!valid(token)) { socket.close(); return }
                    pending = socket
                }
                socket.connect(InetSocketAddress(settings.host, settings.port), 5_000)
                if (attach(token, socket)) readPeer(token, socket, false)
            }
        } catch (_: Exception) {
            retryAfterFailure(token)
        }
    }

    private fun attach(token: Long, socket: Socket): Boolean = synchronized(lock) {
        if (!valid(token) || peers.size >= 16) { socket.close(); return false }
        socket.tcpNoDelay = true
        socket.keepAlive = true
        if (pending === socket) pending = null
        peers.add(socket)
        backoff.reset()
        onState("connected", peers.size)
        true
    }

    private fun readPeer(token: Long, socket: Socket, relay: Boolean) {
        try {
            val input = socket.getInputStream()
            val frame = ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            while (true) {
                val size = input.read(chunk)
                if (size < 0) break
                for (index in 0 until size) {
                    val value = chunk[index].toInt() and 255
                    if (value == 10) {
                        if (frame.size() > 0) {
                            val bytes = frame.toByteArray()
                            frame.reset()
                            if (!synchronized(lock) { valid(token) }) return
                            // Invalid or already-seen messages are neither spoken nor relayed.
                            val outgoing = onFrame(bytes)
                            if (outgoing != null && relay) broadcast(outgoing, socket, token)
                        }
                    } else {
                        check(frame.size() < 64 * 1024) { "Oversized frame" }
                        frame.write(value)
                    }
                }
            }
        } catch (_: Exception) {
            // No raw packet or exception text is logged (it can contain message data).
        } finally {
            synchronized(lock) {
                peers.remove(socket)
                runCatching { socket.close() }
                if (valid(token)) {
                    if (relay) onState(if (peers.isEmpty()) "listening" else "connected", peers.size)
                    else scheduleLocked(backoff.nextDelay(), "reconnecting")
                }
            }
        }
    }

    private fun retryAfterFailure(token: Long) = synchronized(lock) {
        if (valid(token)) scheduleLocked(backoff.nextDelay(), "reconnecting")
    }

    fun send(frame: ByteArray) {
        require(frame.size <= 64 * 1024 && frame.lastOrNull() == 10.toByte())
        val token = synchronized(lock) { check(requested && !closed); epoch }
        check(broadcast(frame, null, token)) { "No TCP peer connected" }
    }

    private fun broadcast(frame: ByteArray, exclude: Socket?, token: Long): Boolean {
        val targets = synchronized(lock) { if (valid(token)) peers.filter { it !== exclude } else emptyList() }
        var sent = false
        for (peer in targets) {
            try {
                synchronized(peer) {
                    check(synchronized(lock) { valid(token) })
                    peer.getOutputStream().write(frame)
                    peer.getOutputStream().flush()
                }
                sent = true
            } catch (_: Exception) { runCatching { peer.close() } }
        }
        return sent
    }

    fun stop() = synchronized(lock) {
        requested = false
        epoch++
        retry?.cancel(false)
        retry = null
        closeSocketsLocked()
        onState("disconnected", 0)
    }

    private fun closeSocketsLocked() {
        runCatching { server?.close() }; server = null
        runCatching { pending?.close() }; pending = null
        peers.forEach { runCatching { it.close() } }; peers.clear()
    }

    override fun close() {
        synchronized(lock) { stop(); closed = true }
        scheduler.shutdownNow()
        io.shutdownNow()
    }
}
