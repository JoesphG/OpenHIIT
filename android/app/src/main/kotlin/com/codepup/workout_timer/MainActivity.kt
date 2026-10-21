package com.codepup.workout_timer

import android.os.Build
import android.util.Log
import android.view.WindowManager
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
 * Dart calls publish({path, json}) to share the run snapshot or timer list as
 * Data Layer items, and runEnded when a run closes; commands from the watch
 * arrive as messages and are passed to Dart.
 */
class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    publish(call.argument<String>("path")!!, call.argument<String>("json")!!)
                    result.success(null)
                }
                "runEnded" -> {
                    showOverLockScreen(false)
                    result.success(null)
                }
                else -> result.notImplemented()
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
        if (event.path == PING_PATH) {
            // Clock sync: echo the watch's send time with ours, straight away.
            val reply = "${String(event.data)}:${System.currentTimeMillis()}"
            Wearable.getMessageClient(this)
                .sendMessage(event.sourceNodeId, PONG_PATH, reply.toByteArray())
            return
        }
        if (event.path != COMMAND_PATH) {
            return
        }
        val command = String(event.data)
        Log.i(TAG, "Watch command '$command' (engine attached: ${channel != null})")
        runOnUiThread {
            // Let a run started from the watch show over the lock screen when
            // the phone is woken mid-workout; the phone stays locked.
            if (command.startsWith("start:")) {
                showOverLockScreen(true)
            }
            channel?.invokeMethod("command", command)
        }
    }

    private fun showOverLockScreen(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (show) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    private fun publish(path: String, json: String) {
        val request = PutDataMapRequest.create(path).apply {
            dataMap.putString("json", json)
            // Always changes, so the watch is notified even for repeat snapshots.
            dataMap.putLong("ts", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(request)
            .addOnSuccessListener { Log.i(TAG, "Published $path") }
            .addOnFailureListener { Log.d(TAG, "No watch to publish to", it) }
    }

    companion object {
        private const val TAG = "WearSync"
        private const val CHANNEL = "openhiit/wear"
        private const val COMMAND_PATH = "/openhiit/command"
        private const val PING_PATH = "/openhiit/ping"
        private const val PONG_PATH = "/openhiit/pong"
    }
}
