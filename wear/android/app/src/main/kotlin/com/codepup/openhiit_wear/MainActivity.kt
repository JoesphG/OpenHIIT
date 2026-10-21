package com.codepup.openhiit_wear

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and bridges it to the Wearable Data Layer.
 *
 * Dart calls: getState, command(String), vibrate(String), keepScreenOn(Boolean).
 * Kotlin calls into Dart: state(String?) whenever the phone publishes a snapshot,
 * and heartRate(Double) with live readings while the app is visible.
 */
class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {
    private var channel: MethodChannel? = null
    private lateinit var heartRate: HeartRateMonitor

    private val heartRatePermission =
        if (Build.VERSION.SDK_INT >= 36) {
            "android.permission.health.READ_HEART_RATE"
        } else {
            Manifest.permission.BODY_SENSORS
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        heartRate = HeartRateMonitor(this) { bpm ->
            runOnUiThread { channel?.invokeMethod("heartRate", bpm) }
        }

        val missing = listOfNotNull(
            heartRatePermission,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.POST_NOTIFICATIONS
            } else {
                null
            },
        ).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            requestPermissions(missing.toTypedArray(), 1)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (isForeground) {
            startHeartRate()
        }
    }

    private fun startHeartRate() {
        if (checkSelfPermission(heartRatePermission) == PackageManager.PERMISSION_GRANTED) {
            heartRate.start()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WearProtocol.CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> fetchState { result.success(it) }
                "command" -> {
                    sendCommand(call.arguments as String)
                    result.success(null)
                }
                "vibrate" -> {
                    vibrate(call.arguments as String)
                    result.success(null)
                }
                "keepScreenOn" -> {
                    setKeepScreenOn(call.arguments as Boolean)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        RunListenerService.cancelNotification(this)
        startHeartRate()
        Wearable.getDataClient(this).addListener(this)
        // Catch up on anything published while we were in the background.
        fetchState { json -> channel?.invokeMethod("state", json) }
    }

    override fun onPause() {
        isForeground = false
        heartRate.stop()
        Wearable.getDataClient(this).removeListener(this)
        super.onPause()
    }

    override fun onDataChanged(events: DataEventBuffer) {
        // The buffer is only valid during this call, so read it straight away.
        val json = events
            .filter {
                it.type == DataEvent.TYPE_CHANGED &&
                    it.dataItem.uri.path == WearProtocol.RUN_PATH
            }
            .map { WearProtocol.json(it.dataItem) }
            .lastOrNull() ?: return
        runOnUiThread { channel?.invokeMethod("state", json) }
    }

    /** Reads the latest run snapshot from any connected phone. */
    private fun fetchState(callback: (String?) -> Unit) {
        Wearable.getDataClient(this)
            .getDataItems(WearProtocol.runUri)
            .addOnSuccessListener { buffer ->
                val json = buffer
                    .maxByOrNull { WearProtocol.timestamp(it) }
                    ?.let { WearProtocol.json(it) }
                buffer.release()
                callback(json)
            }
            .addOnFailureListener { callback(null) }
    }

    private fun sendCommand(command: String) {
        val messages = Wearable.getMessageClient(this)
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            nodes.forEach {
                messages.sendMessage(it.id, WearProtocol.COMMAND_PATH, command.toByteArray())
            }
        }
    }

    private fun vibrate(pattern: String) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val effect = when (pattern) {
            "tick" -> VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE)
            "done" -> VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300, 150, 600), -1)
            else -> VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        vibrator.vibrate(effect)
    }

    private fun setKeepScreenOn(on: Boolean) {
        runOnUiThread {
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    companion object {
        /** Read by [RunListenerService] to skip the notification when visible. */
        @Volatile
        var isForeground = false
    }
}
