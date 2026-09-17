package com.sih.voicebridge.location

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.content.ContextCompat

class LocationHelper(private val context: Context) : LocationListener {

    private val locationManager: LocationManager? =
        context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    @Volatile
    private var cachedLocation: Location? = null

    private var isListening = false

    fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @SuppressLint("MissingPermission")
    fun startListening() {
        if (!hasLocationPermission() || locationManager == null || isListening) {
            return
        }

        try {
            // Update last known location immediately
            updateFromLastKnown()

            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    5000L, // 5 seconds
                    2.0f,  // 2 meters
                    this,
                    Looper.getMainLooper()
                )
            }

            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    10000L,
                    5.0f,
                    this,
                    Looper.getMainLooper()
                )
            }

            isListening = true
        } catch (_: SecurityException) {
        } catch (_: Throwable) {
        }
    }

    fun stopListening() {
        if (!isListening || locationManager == null) return
        try {
            locationManager.removeUpdates(this)
        } catch (_: Throwable) {
        } finally {
            isListening = false
        }
    }

    @SuppressLint("MissingPermission")
    fun getCurrentLocation(): Map<String, Any?>? {
        if (!hasLocationPermission() || locationManager == null) {
            return null
        }

        if (cachedLocation == null) {
            updateFromLastKnown()
        }

        val loc = cachedLocation ?: return null
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "altitude" to if (loc.hasAltitude()) loc.altitude else null,
            "accuracy" to if (loc.hasAccuracy()) loc.accuracy.toDouble() else null,
            "timestamp" to loc.time,
            "provider" to loc.provider
        )
    }

    @SuppressLint("MissingPermission")
    private fun updateFromLastKnown() {
        if (locationManager == null || !hasLocationPermission()) return

        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )

        for (provider in providers) {
            try {
                if (locationManager.isProviderEnabled(provider)) {
                    val loc = locationManager.getLastKnownLocation(provider)
                    if (loc != null) {
                        val current = cachedLocation
                        if (current == null || loc.time > current.time || loc.accuracy < current.accuracy) {
                            cachedLocation = loc
                        }
                    }
                }
            } catch (_: SecurityException) {
            } catch (_: Throwable) {
            }
        }
    }

    override fun onLocationChanged(location: Location) {
        cachedLocation = location
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onProviderEnabled(provider: String) {}

    override fun onProviderDisabled(provider: String) {}
}
