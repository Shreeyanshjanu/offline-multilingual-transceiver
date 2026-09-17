
package com.sih.voicebridge

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.sih.voicebridge.bridge.NativeBridgeHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val MICROPHONE_PERMISSION_REQUEST_CODE = 9101
        private const val LOCATION_PERMISSION_REQUEST_CODE = 9102
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 9103
    }

    private lateinit var nativeBridgeHandler: NativeBridgeHandler
    private var pendingLocationPermission: MethodChannel.Result? = null
    private var pendingNotificationPermission: MethodChannel.Result? = null
    private var notificationDecision: Boolean? = null
    private var visible = false

    override fun onResume() {
        super.onResume()
        visible = true
        deliverNotificationDecision()
    }
    override fun onPause() { visible = false; super.onPause() }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine,
    ) {
        super.configureFlutterEngine(flutterEngine)

        ensureMicrophonePermission()

        nativeBridgeHandler =
            NativeBridgeHandler(this, ::requestLocationPermission, { visible }, ::requestNotificationPermission)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.sih.voicebridge/native",
        ).setMethodCallHandler(
            nativeBridgeHandler
        )

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.sih.voicebridge/native_events",
        ).setStreamHandler(
            nativeBridgeHandler
        )
    }

    private fun ensureMicrophonePermission() {
        if (
            checkSelfPermission(
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST_CODE,
        )
    }

    private fun requestLocationPermission(result: MethodChannel.Result) {
        if (pendingLocationPermission != null) {
            result.success(false)
            return
        }
        pendingLocationPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            LOCATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingNotificationPermission != null) { result.success(false); return }
        pendingNotificationPermission = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            notificationDecision = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            deliverNotificationDecision()
        }
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            pendingLocationPermission?.success(granted)
            pendingLocationPermission = null
        }
    }

    private fun deliverNotificationDecision() {
        val decision = notificationDecision ?: return
        if (!visible) return
        pendingNotificationPermission?.success(decision)
        pendingNotificationPermission = null
        notificationDecision = null
    }

    override fun onDestroy() {
        pendingNotificationPermission?.success(false)
        pendingNotificationPermission = null
        pendingLocationPermission?.success(false)
        pendingLocationPermission = null
        if (::nativeBridgeHandler.isInitialized) {
            nativeBridgeHandler.dispose()
        }

        super.onDestroy()
    }
}
