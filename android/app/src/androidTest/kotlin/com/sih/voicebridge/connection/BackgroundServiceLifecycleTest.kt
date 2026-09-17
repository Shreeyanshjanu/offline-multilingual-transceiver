package com.sih.voicebridge.connection

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sih.voicebridge.MainActivity
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.Socket

/** Opt-in only: removes this app's task and changes connection preferences on a test emulator. */
@RunWith(AndroidJUnit4::class)
class BackgroundServiceLifecycleTest {
    @Test fun serviceSurvivesTaskRemovalAndNotificationDisconnectCancelsIt() {
        assumeTrue("Run only on a disposable emulator with -e allowServiceLifecycle true",
            InstrumentationRegistry.getArguments().getString("allowServiceLifecycle") == "true" &&
                (Build.HARDWARE == "ranchu" || Build.HARDWARE == "goldfish"))
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val repository = ConnectionRepository.get(context)
        assumeTrue("An existing user connection must not be interrupted", !repository.requested())
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        // A visible activity in the desktop emulator can be resumed without keyboard focus.
        instrumentation.waitForIdleSync()
        repository.setEnabled(true)
        val generation = repository.requestConnection(ConnectionConfig(true, ""))
        var peer: Socket? = null
        try {
            instrumentation.runOnMainSync {
                ContextCompat.startForegroundService(context, Intent(context, ConnectionForegroundService::class.java)
                    .setAction(ConnectionForegroundService.ACTION_CONNECT)
                    .putExtra(ConnectionForegroundService.EXTRA_GENERATION, generation))
            }
            awaitCondition { ConnectionRuntime.status(context)["state"] == "listening" }
            peer = Socket("127.0.0.1", 7070).apply { soTimeout = 5_000 }
            awaitCondition { ConnectionRuntime.status(context)["connected"] == true }
            val originalService = ConnectionRuntime.service
            val incomingId = "lifecycle-in-${System.nanoTime()}"
            val message = JSONObject().put("id", incomingId).put("message", "Background lifecycle verification")
                .put("language", "en").put("type", "speech").put("timestamp", System.currentTimeMillis())
            instrumentation.runOnMainSync {
                context.getSystemService(ActivityManager::class.java).appTasks.forEach { it.finishAndRemoveTask() }
            }
            awaitCondition { activity.isDestroyed }
            assertSame(originalService, ConnectionRuntime.service)
            repeat(2) { peer.getOutputStream().write(MessageWireCodec.encode(message)) }
            awaitCondition { repository.messages().any { (it["wire"] as Map<*, *>)["id"] == incomingId } }
            assertEquals(1, repository.messages().count { (it["wire"] as Map<*, *>)["id"] == incomingId })
            assertTrue(ConnectionRuntime.status(context)["connected"] == true)

            val outgoing = JSONObject(message.toString()).put("id", "lifecycle-out-${System.nanoTime()}")
            originalService!!.send(MessageWireCodec.encode(outgoing))
            val received = peer.getInputStream().bufferedReader().readLine()
            assertEquals(outgoing.getString("id"), JSONObject(received).getString("id"))

            instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            assertSame(originalService, ConnectionRuntime.service)
            assertEquals(1, originalService.snapshot()["peerCount"])
            val notification = context.getSystemService(NotificationManager::class.java)
                .activeNotifications.first { it.id == 7070 }.notification
            assertFalse(notification.extras.toString().contains(message.getString("message")))
            notification.actions.single().actionIntent.send()
            awaitCondition { ConnectionRuntime.service == null }
            assertFalse(repository.requested())
            assertEquals(-1, peer.getInputStream().read())
            Thread.sleep(1_200)
            assertNull(ConnectionRuntime.service)
            assertFalse(repository.accepts(generation))
        } finally {
            peer?.close()
            repository.setEnabled(false)
            ConnectionRuntime.service?.disconnectImmediately()
            instrumentation.runOnMainSync {
                context.getSystemService(ActivityManager::class.java).appTasks.forEach { it.finishAndRemoveTask() }
            }
        }
    }

    private fun awaitCondition(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (!condition() && System.nanoTime() < deadline) Thread.sleep(50)
        assertTrue("Timed out waiting for native lifecycle transition", condition())
    }
}
