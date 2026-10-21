package com.codepup.workout_timer

import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the run timer to the Wear OS app (see wear/).
 *
 * Dart calls publish(json) to share the run snapshot as a Data Layer item;
 * commands from the watch arrive as messages and are passed to Dart.
 */
class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "publish") {
                publish(call.arguments as String)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        // Registered for the engine's lifetime so commands still arrive while
        // the phone screen is off mid-workout.
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Wearable.getMessageClient(this).removeListener(this)
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != COMMAND_PATH) {
            return
        }
        val command = String(event.data)
        runOnUiThread { channel?.invokeMethod("command", command) }
    }

    private fun publish(json: String) {
        val request = PutDataMapRequest.create(RUN_PATH).apply {
            dataMap.putString("json", json)
            // Always changes, so the watch is notified even for repeat snapshots.
            dataMap.putLong("ts", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(request)
            .addOnFailureListener { Log.d(TAG, "No watch to publish to", it) }
    }

    companion object {
        private const val TAG = "WearSync"
        private const val CHANNEL = "openhiit/wear"
        private const val RUN_PATH = "/openhiit/run"
        private const val COMMAND_PATH = "/openhiit/command"
    }
}
