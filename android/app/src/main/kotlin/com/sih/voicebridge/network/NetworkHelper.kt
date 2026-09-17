package com.sih.voicebridge.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import java.net.Inet4Address

/**
 * Utility for local offline Wi-Fi network inspection.
 * Fetches the active IPv4 Gateway / Hotspot Host IP address directly from Android system networking.
 */
class NetworkHelper(private val context: Context) {

    fun getWifiGatewayIp(): String? {
        try {
            // Strategy 1: Modern Android LinkProperties via ConnectivityManager
            val connectivityManager =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (connectivityManager != null) {
                for (network in connectivityManager.allNetworks) {
                    val caps = connectivityManager.getNetworkCapabilities(network) ?: continue
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                        val lp = connectivityManager.getLinkProperties(network) ?: continue

                        // Android 11+ (API 30+): dhcpServerAddress is directly exposed
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val dhcpServer = lp.dhcpServerAddress?.hostAddress
                            if (!dhcpServer.isNullOrEmpty() && isValidIpv4Gateway(dhcpServer)) {
                                return dhcpServer
                            }
                        }

                        // Inspect routes for default IPv4 gateway route (0.0.0.0/0)
                        for (route in lp.routes) {
                            if (route.isDefaultRoute) {
                                val gateway = route.gateway
                                if (gateway is Inet4Address) {
                                    val ip = gateway.hostAddress
                                    if (!ip.isNullOrEmpty() && isValidIpv4Gateway(ip)) {
                                        return ip
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Strategy 2: Universal WifiManager DhcpInfo fallback
            val wifiManager =
                context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            val dhcpInfo = wifiManager?.dhcpInfo
            if (dhcpInfo != null) {
                if (dhcpInfo.gateway != 0) {
                    val gw = formatIp(dhcpInfo.gateway)
                    if (isValidIpv4Gateway(gw)) {
                        return gw
                    }
                }
                if (dhcpInfo.serverAddress != 0) {
                    val srv = formatIp(dhcpInfo.serverAddress)
                    if (isValidIpv4Gateway(srv)) {
                        return srv
                    }
                }
            }
        } catch (_: Throwable) {
            // Silently ignore permission/sandbox exceptions
        }
        return null
    }

    private fun formatIp(ipInt: Int): String {
        return String.format(
            "%d.%d.%d.%d",
            ipInt and 0xff,
            ipInt shr 8 and 0xff,
            ipInt shr 16 and 0xff,
            ipInt shr 24 and 0xff
        )
    }

    private fun isValidIpv4Gateway(ip: String): Boolean {
        return ip.isNotBlank() && ip != "0.0.0.0" && ip != "127.0.0.1"
    }
}
