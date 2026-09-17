package com.sih.voicebridge.bridge

import java.util.concurrent.CopyOnWriteArraySet

/** In-process UI observation only. Services never depend on a Flutter listener. */
internal object NativeEventHub {
    private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()
    fun add(listener: (Map<String, Any?>) -> Unit) { listeners.add(listener) }
    fun remove(listener: (Map<String, Any?>) -> Unit) { listeners.remove(listener) }
    fun emit(event: Map<String, Any?>) {
        val stamped = if (event.containsKey("timestampEpochMs")) event else
            event + ("timestampEpochMs" to System.currentTimeMillis())
        listeners.forEach { listener -> runCatching { listener(stamped) } }
    }
}
