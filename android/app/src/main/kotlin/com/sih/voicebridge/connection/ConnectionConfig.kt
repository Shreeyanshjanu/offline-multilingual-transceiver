package com.sih.voicebridge.connection

internal data class ConnectionConfig(val runAsServer: Boolean, val host: String, val port: Int = 7070) {
    init {
        require(port == 7070) { "iTantra uses port 7070" }
        require(host.length <= 253 && host.none { it.isWhitespace() || it == '/' }) { "Invalid host" }
        require(runAsServer || host.isNotBlank()) { "Enter the leader IP address" }
    }
}

internal class ReconnectBackoff {
    private var index = 0
    private val delays = longArrayOf(1_000, 2_000, 4_000, 8_000, 15_000, 30_000)
    fun nextDelay(): Long = delays[index.also { if (index < delays.lastIndex) index++ }]
    fun reset() { index = 0 }
}
