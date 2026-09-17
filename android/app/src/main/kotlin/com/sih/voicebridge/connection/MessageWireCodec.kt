package com.sih.voicebridge.connection

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/** The existing SpeechMessage JSON protocol, delimited by one UTF-8 newline. */
internal object MessageWireCodec {
    const val MAX_BYTES = 64 * 1024

    fun decode(frame: ByteArray): JSONObject {
        require(frame.size <= MAX_BYTES) { "Oversized message" }
        val text = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(frame)).toString()
        val raw = JSONObject(text)
        require(raw.opt("message") is String) { "Missing message text" }
        val message = raw.getString("message")
        require(message.isNotBlank()) { "Empty message" }
        val id = raw.opt("id")?.takeUnless { it == JSONObject.NULL }?.toString()
            ?: "legacy-" + MessageDigest.getInstance("SHA-256").digest(frame).joinToString("") { "%02x".format(it) }
        require(id.isNotBlank() && id.length <= 160) { "Invalid message ID" }
        val language = raw.optString("language", "en")
        require(language.matches(Regex("[a-zA-Z]{2,8}([_-][a-zA-Z0-9]{1,8})*")) && language.length <= 35) { "Invalid language" }
        val type = raw.optString("type", "speech").let { if (it in setOf("speech", "emergency")) it else "system" }
        val timestampRaw = raw.opt("timestamp") ?: raw.opt("timestampEpochMs")
        val timestamp = when (timestampRaw) {
            is Number -> timestampRaw.toLong()
            is String -> timestampRaw.toLongOrNull()
            else -> null
        } ?: System.currentTimeMillis()
        require(timestamp in 0..8_640_000_000_000_000L) { "Invalid timestamp" }
        val result = JSONObject().put("id", id).put("type", type).put("language", language)
            .put("message", message).put("timestamp", timestamp)
        val sender = raw.optJSONObject("sender")
        val normalizedSender = JSONObject()
        for ((field, legacy) in listOf("callsign" to "senderCallsign", "role" to "senderRole", "squad" to "senderSquad")) {
            val value = sender?.opt(field) ?: if (field == "callsign") sender?.opt("name") ?: raw.opt(legacy) ?: raw.opt("senderName") else raw.opt(legacy)
            if (value != null && value != JSONObject.NULL) {
                require(value is String && value.length <= 256) { "Invalid sender metadata" }
                normalizedSender.put(field, value)
            }
        }
        if (normalizedSender.length() > 0) result.put("sender", normalizedSender)
        val location = raw.optJSONObject("location") ?: raw.takeIf { it.has("lat") && it.has("lng") }
        if (location != null) {
            val lat = location.getDouble("lat")
            val lng = location.getDouble("lng")
            require(lat.isFinite() && lat in -90.0..90.0 && lng.isFinite() && lng in -180.0..180.0) { "Invalid coordinates" }
            val normalized = JSONObject().put("lat", lat).put("lng", lng)
            for ((key, alias) in listOf("acc" to "accuracy", "alt" to "altitude", "timestamp" to "timestamp")) {
                val sourceKey = if (location.has(key)) key else alias
                if (location.has(sourceKey) && !location.isNull(sourceKey)) {
                    val value = location.getDouble(sourceKey)
                    require(value.isFinite()) { "Invalid location metadata" }
                    if (key == "timestamp") normalized.put(key, value.toLong()) else normalized.put(key, value)
                }
            }
            if (location.has("provider")) {
                val provider = location.getString("provider")
                require(provider.length <= 64) { "Invalid provider" }
                normalized.put("provider", provider)
            }
            result.put("location", normalized)
        }
        require(encode(result).size <= MAX_BYTES) { "Oversized message" }
        return result
    }

    fun encode(message: JSONObject): ByteArray = (message.toString() + "\n").toByteArray(Charsets.UTF_8)

    fun toMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key -> platformValue(json.get(key)) }
    private fun platformValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(value)
        is JSONArray -> (0 until value.length()).map { platformValue(value.get(it)) }
        else -> value
    }
}
