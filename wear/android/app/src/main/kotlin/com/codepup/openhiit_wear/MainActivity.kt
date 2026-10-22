package com.codepup.openhiit_wear

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.InputDevice
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import androidx.core.view.ViewConfigurationCompat
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
 * Dart calls: getState, getTimers, command(String), vibrate(String),
 * keepScreenOn(Boolean), runShowing(Boolean).
 * Kotlin calls into Dart: state(String?) whenever the phone publishes a snapshot,
 * timers(String?) when its timer list changes, rotary(Double) with crown
 * scrolling in logical pixels,
 * and heartRate(Double) with live readings while the app is visible.
 */
class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {
    private var channel: MethodChannel? = null
    private lateinit var heartRate: HeartRateMonitor

    // Set by Dart while a run is on screen.
    private var runShowing = false

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
                "getState" -> fetch(WearProtocol.RUN_PATH) { result.success(it) }
                "getTimers" -> fetch(WearProtocol.TIMERS_PATH) { result.success(it) }
                "getClockOffset" -> result.success(ClockSync.offsetMs(this))
                "command" -> {
                    sendCommand(call.arguments as String)
                    result.success(null)
                }
                "vibrate" -> {
                    Haptics.vibrate(this, call.arguments as String)
                    result.success(null)
                }
                "runShowing" -> {
                    runShowing = call.arguments as Boolean
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
        ClockSync.onOffsetChanged = { offset ->
            runOnUiThread { channel?.invokeMethod("clockOffset", offset) }
        }
        ClockSync.measure(this)
        startHeartRate()
        Wearable.getDataClient(this).addListener(this)
        // Catch up on anything published while we were in the background.
        fetch(WearProtocol.RUN_PATH) { json ->
            channel?.invokeMethod("state", json)
            // Opening the app is allowed to start the run alerts, in case
            // Android refused while it was closed.
            RunAlerts.sync(this, json)
        }
        fetch(WearProtocol.TIMERS_PATH) { json -> channel?.invokeMethod("timers", json) }
    }

    override fun onPause() {
        // Swiping the app away mid-run ends the run, like the phone's back
        // button. Leaving any other way (the crown, the screen timing out)
        // doesn't finish the activity, so the run carries on.
        if (isFinishing && runShowing) {
            runShowing = false
            sendCommand("stop")
        }
        isForeground = false
        ClockSync.onOffsetChanged = null
        heartRate.stop()
        Wearable.getDataClient(this).removeListener(this)
        super.onPause()
    }

    // Flutter doesn't receive the crown, so forward its scrolling to Dart.
    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_SCROLL &&
            event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            val pixels = -event.getAxisValue(MotionEvent.AXIS_SCROLL) *
                ViewConfigurationCompat.getScaledVerticalScrollFactor(
                    ViewConfiguration.get(this), this,
                )
            channel?.invokeMethod("rotary", (pixels / resources.displayMetrics.density).toDouble())
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onDataChanged(events: DataEventBuffer) {
        // The buffer is only valid during this call, so read it straight away.
        val latest = events
            .filter { it.type == DataEvent.TYPE_CHANGED }
            .associate { it.dataItem.uri.path to WearProtocol.json(it.dataItem) }
        runOnUiThread {
            latest[WearProtocol.RUN_PATH]?.let { channel?.invokeMethod("state", it) }
            latest[WearProtocol.TIMERS_PATH]?.let { channel?.invokeMethod("timers", it) }
        }
    }

    /** Reads the latest JSON published at [path] by any connected phone. */
    private fun fetch(path: String, callback: (String?) -> Unit) {
        Wearable.getDataClient(this)
            .getDataItems(WearProtocol.uri(path))
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
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                Log.i(TAG, "Sending '$command' to ${nodes.size} phone(s)")
                nodes.forEach { node ->
                    messages.sendMessage(node.id, WearProtocol.COMMAND_PATH, command.toByteArray())
                        .addOnFailureListener { Log.w(TAG, "Send to ${node.displayName} failed", it) }
                }
            }
            .addOnFailureListener { Log.w(TAG, "Couldn't list phones", it) }
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
        private const val TAG = "OpenHiitWear"

        /** Read by [RunListenerService] to skip the notification when visible. */
        @Volatile
        var isForeground = false
    }
}
