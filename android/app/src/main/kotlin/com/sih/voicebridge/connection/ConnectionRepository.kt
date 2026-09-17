package com.sih.voicebridge.connection

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A bounded, atomic SharedPreferences journal. All writes run on worker threads. */
internal class ConnectionRepository(context: Context, preferencesName: String = "itantra_connection") {
    companion object {
        private var instance: ConnectionRepository? = null
        @Synchronized fun get(context: Context): ConnectionRepository = instance
            ?: ConnectionRepository(context.applicationContext).also { instance = it }
        const val MAX_MESSAGES = 200
        const val MAX_JOURNAL_BYTES = 512 * 1024
    }
    private val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val records = runCatching { JSONArray(preferences.getString("messages", "[]")) }.getOrDefault(JSONArray())
    private val seen = runCatching { JSONArray(preferences.getString("seen_ids", "[]")) }.getOrDefault(JSONArray())

    @Synchronized fun enabled() = preferences.getBoolean("background_connection_enabled", false)
    @Synchronized fun requested() = preferences.getBoolean("connection_requested", false)
    @Synchronized fun generation() = preferences.getLong("generation", 0)
    @Synchronized fun config() = ConnectionConfig(
        preferences.getBoolean("run_as_server", true), preferences.getString("host", "") ?: "",
        preferences.getInt("port", 7070),
    )

    @Synchronized fun setEnabled(enabled: Boolean) {
        val editor = preferences.edit().putBoolean("background_connection_enabled", enabled)
        if (!enabled) editor.putBoolean("connection_requested", false)
            .putLong("generation", generation() + 1).putString("last_known_connection_state", "disconnected")
        check(editor.commit()) { "Could not save connection preference" }
    }

    @Synchronized fun requestConnection(config: ConnectionConfig): Long {
        check(enabled()) { "Enable background connection first" }
        val token = generation() + 1
        check(preferences.edit().putBoolean("connection_requested", true)
            .putBoolean("run_as_server", config.runAsServer).putString("host", config.host)
            .putInt("port", config.port).putLong("generation", token)
            .putString("last_known_connection_state", "connecting").commit()) { "Could not save connection" }
        return token
    }

    @Synchronized fun disconnect() {
        check(preferences.edit().putBoolean("connection_requested", false)
            .putLong("generation", generation() + 1)
            .putString("last_known_connection_state", "disconnected").commit()) { "Could not save disconnect" }
    }

    @Synchronized fun accepts(token: Long) = enabled() && requested() && token == generation()
    @Synchronized fun saveLanguage(code: String) { preferences.edit().putString("language_code", code).commit() }
    @Synchronized fun saveState(token: Long, state: String) {
        if (accepts(token)) preferences.edit().putString("last_known_connection_state", state).commit()
    }

    @Synchronized fun status(): Map<String, Any?> {
        val config = config()
        return mapOf("backgroundEnabled" to enabled(), "connectionRequested" to requested(),
            "generation" to generation(), "runAsServer" to config.runAsServer,
            "languageCode" to preferences.getString("language_code", null),
            "mode" to if (config.runAsServer) "server" else "client", "host" to config.host, "port" to config.port,
            "lastKnownState" to preferences.getString("last_known_connection_state", "disconnected"),
            "unreadCount" to (0 until records.length()).count { !records.getJSONObject(it).optBoolean("read", true) })
    }

    @Synchronized fun add(message: JSONObject, origin: String): Map<String, Any?>? {
        val id = message.getString("id")
        if ((0 until seen.length()).any { seen.getString(it) == id }) return null
        val next = JSONArray(records.toString())
        val nextSeen = JSONArray(seen.toString())
        val record = JSONObject().put("wire", message).put("origin", origin)
            .put("receivedAt", System.currentTimeMillis()).put("read", origin != "remote")
            .put("playback", if (origin == "remote") "queued" else "not_requested")
        next.put(record)
        nextSeen.put(id)
        while (next.length() > MAX_MESSAGES || next.toString().toByteArray(Charsets.UTF_8).size > MAX_JOURNAL_BYTES) next.remove(0)
        while (nextSeen.length() > 1000) nextSeen.remove(0)
        commitJournal(next, nextSeen)
        return MessageWireCodec.toMap(record)
    }

    @Synchronized fun messages(): List<Map<String, Any?>> =
        (0 until records.length()).map { MessageWireCodec.toMap(records.getJSONObject(it)) }

    @Synchronized fun acknowledge(ids: Set<String>) {
        val next = JSONArray(records.toString())
        for (i in 0 until next.length()) {
            val record = next.getJSONObject(i)
            if (record.getJSONObject("wire").getString("id") in ids) record.put("read", true)
        }
        commitJournal(next, seen)
    }

    @Synchronized fun playbackEvent(event: Map<String, Any?>) {
        val id = event["messageId"] as? String ?: return
        val type = event["type"] as? String ?: return
        if (type !in setOf("tts_started", "audio_started", "playback_finished", "error")) return
        val next = JSONArray(records.toString())
        val record = (0 until next.length()).map { next.getJSONObject(it) }
            .firstOrNull { it.getJSONObject("wire").getString("id") == id } ?: return
        if (type != "playback_finished" || !record.has("playbackError")) record.put("playback", type)
        if (type == "tts_started" || type == "audio_started") record.put(type, event["timestampEpochMs"])
        if (type == "error") record.put("playbackError", "Speech playback unavailable. Check installed offline voices.")
        commitJournal(next, seen)
    }

    @Synchronized fun clearMessages() {
        // Retain seen IDs so clearing history cannot cause old packets to speak again.
        commitJournal(JSONArray(), seen)
    }

    private fun commitJournal(next: JSONArray, nextSeen: JSONArray) {
        check(preferences.edit().putString("messages", next.toString())
            .putString("seen_ids", nextSeen.toString()).commit()) { "Could not store message history" }
        val serializedSeen = nextSeen.toString()
        while (records.length() > 0) records.remove(0)
        for (i in 0 until next.length()) records.put(next.get(i))
        while (seen.length() > 0) seen.remove(0)
        val copySeen = JSONArray(serializedSeen)
        for (i in 0 until copySeen.length()) seen.put(copySeen.get(i))
    }
}
