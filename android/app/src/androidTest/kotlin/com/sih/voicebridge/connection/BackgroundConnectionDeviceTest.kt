package com.sih.voicebridge.connection

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackgroundConnectionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun protocolRetainsUnicodeSenderAndGps() {
        val wire = JSONObject().put("id", "protocol-test").put("message", "नमस्ते 🌍")
            .put("language", "hi").put("type", "emergency").put("timestamp", 1234L)
            .put("sender", JSONObject().put("callsign", "Test"))
            .put("location", JSONObject().put("lat", 12.0).put("lng", 77.0).put("acc", 4.0)
                .put("alt", 21.0).put("provider", "gps").put("timestamp", 1234L))
        val decoded = MessageWireCodec.decode(MessageWireCodec.encode(wire))
        assertEquals("नमस्ते 🌍", decoded.getString("message"))
        assertEquals("Test", decoded.getJSONObject("sender").getString("callsign"))
        assertEquals(4.0, decoded.getJSONObject("location").getDouble("acc"), 0.0)
        assertEquals(21.0, decoded.getJSONObject("location").getDouble("alt"), 0.0)
        assertEquals("gps", decoded.getJSONObject("location").getString("provider"))
        assertEquals("emergency", decoded.getString("type"))
    }

    @Test fun rejectsInvalidUtf8AndMissingMessage() {
        assertTrue(runCatching { MessageWireCodec.decode(byteArrayOf(0xC3.toByte(), 0x28)) }.isFailure)
        assertTrue(runCatching { MessageWireCodec.decode("{\"id\":1}".toByteArray()) }.isFailure)
        assertTrue(runCatching { MessageWireCodec.decode("{\"message\":\"x\",\"location\":{\"lat\":999,\"lng\":0}}".toByteArray()) }.isFailure)
    }

    @Test fun journalSurvivesRecreationDeduplicatesAndManualDisconnectWins() {
        val name = "itantra_connection_test_${System.nanoTime()}"
        try {
            val first = ConnectionRepository(context, name)
            first.setEnabled(true)
            val generation = first.requestConnection(ConnectionConfig(true, ""))
            val message = MessageWireCodec.decode("{\"id\":\"persistent-test\",\"message\":\"Background test\",\"language\":\"en\"}".toByteArray())
            assertNotNull(first.add(message, "remote"))
            assertNull(first.add(message, "remote"))
            val restored = ConnectionRepository(context, name)
            assertEquals(1, restored.messages().size)
            assertEquals(1, restored.status()["unreadCount"])
            restored.acknowledge(setOf("persistent-test"))
            assertEquals(0, restored.status()["unreadCount"])
            restored.disconnect()
            assertFalse(restored.accepts(generation))
            assertFalse(ConnectionRepository(context, name).requested())
            restored.clearMessages()
            assertNull(restored.add(message, "remote"))
        } finally { context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear().commit() }
    }
}
