package com.sih.voicebridge.connection

import org.junit.Assert.*
import org.junit.Test
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class NativeTcpConnectionTest {
    @Test fun backoffCapsAndResets() {
        val retry = ReconnectBackoff()
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 15000L, 30000L, 30000L), List(7) { retry.nextDelay() })
        retry.reset()
        assertEquals(1000L, retry.nextDelay())
    }

    @Test fun serverPreservesSplitUtf8AndRelaysWithoutEcho() {
        val states = LinkedBlockingQueue<String>()
        val received = LinkedBlockingQueue<String>()
        NativeTcpConnection({ state, _ -> states.offer(state) }, { frame ->
            received.offer(frame.toString(Charsets.UTF_8)); frame + byteArrayOf(10)
        }).use { transport ->
            transport.start(ConnectionConfig(true, ""))
            awaitState(states, "listening")
            Socket("127.0.0.1", 7070).use { first ->
                awaitState(states, "connected")
                Socket("127.0.0.1", 7070).use { second ->
                    awaitState(states, "connected")
                    first.soTimeout = 200
                    second.soTimeout = 3000
                    val wire = "{\"message\":\"नमस्ते 🌍\"}"
                    val bytes = (wire + "\n").toByteArray(Charsets.UTF_8)
                    bytes.forEach { first.getOutputStream().write(byteArrayOf(it)) }
                    first.getOutputStream().flush()
                    assertEquals(wire, received.poll(3, TimeUnit.SECONDS))
                    assertEquals(wire, second.getInputStream().bufferedReader(Charsets.UTF_8).readLine())
                    try { first.getInputStream().read(); fail("Sender received its own relay") } catch (_: SocketTimeoutException) { }
                    transport.send("{\"message\":\"host\"}\n".toByteArray())
                    assertEquals("{\"message\":\"host\"}", first.getInputStream().bufferedReader().readLine())
                }
            }
        }
    }

    @Test fun reconnectsAfterPeerLossAndManualStopCancelsRetry() {
        val states = LinkedBlockingQueue<String>()
        val listener = ServerSocket().apply { reuseAddress = true; bind(java.net.InetSocketAddress(7070)); soTimeout = 4000 }
        listener.use {
            NativeTcpConnection({ state, _ -> states.offer(state) }, { null }).use { transport ->
                transport.start(ConnectionConfig(false, "127.0.0.1"))
                listener.accept().use { awaitState(states, "connected") }
                awaitState(states, "reconnecting")
                listener.accept().use { awaitState(states, "connected") }
                awaitState(states, "reconnecting")
                transport.stop()
                listener.soTimeout = 1500
                try { listener.accept().close(); fail("Manual disconnect reconnected") } catch (_: SocketTimeoutException) { }
            }
        }
    }

    @Test fun oversizedFrameClosesOnlyTheOffendingPeer() {
        val states = LinkedBlockingQueue<String>()
        val received = LinkedBlockingQueue<ByteArray>()
        NativeTcpConnection({ state, _ -> states.offer(state) }, { received.offer(it); null }).use { transport ->
            transport.start(ConnectionConfig(true, ""))
            awaitState(states, "listening")
            Socket("127.0.0.1", 7070).use { peer ->
                awaitState(states, "connected")
                peer.soTimeout = 3000
                peer.getOutputStream().write(ByteArray(65537) { 65 })
                runCatching { peer.getOutputStream().flush() }
                awaitState(states, "listening")
                assertTrue(received.isEmpty())
            }
            Socket("127.0.0.1", 7070).use { peer ->
                awaitState(states, "connected")
                peer.getOutputStream().write("ok\n".toByteArray())
                assertEquals("ok", received.poll(3, TimeUnit.SECONDS)?.toString(Charsets.UTF_8))
            }
        }
    }

    private fun awaitState(states: LinkedBlockingQueue<String>, expected: String) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (System.nanoTime() < deadline) {
            if (states.poll(100, TimeUnit.MILLISECONDS) == expected) return
        }
        fail("Did not reach $expected")
    }
}
