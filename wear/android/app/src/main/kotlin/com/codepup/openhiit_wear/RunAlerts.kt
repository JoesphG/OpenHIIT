package com.codepup.openhiit_wear

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import org.json.JSONObject

/** Starts or stops [RunAlertService] to match each run snapshot. */
object RunAlerts {
    private const val TAG = "OpenHiitWear"
    private var lastMeasuredRunId: String? = null

    fun sync(context: Context, json: String?) {
        val active = try {
            json != null && JSONObject(json).optBoolean("active")
        } catch (e: Exception) {
            false
        }
        if (!active) {
            context.stopService(Intent(context, RunAlertService::class.java))
            OngoingRun.cancel(context)
            return
        }
        // Measure the clock offset afresh for each new run.
        val runId = JSONObject(json!!).optString("runId")
        if (runId != lastMeasuredRunId) {
            lastMeasuredRunId = runId
            ClockSync.measure(context)
        }
        try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, RunAlertService::class.java)
                    .putExtra(RunAlertService.EXTRA_JSON, json),
            )
        } catch (e: Exception) {
            // Android may refuse to start the service while the app is in the
            // background. Show the run icon anyway; opening the app from it
            // starts the alerts.
            Log.w(TAG, "Couldn't start run alerts in the background", e)
            OngoingRun.update(context, json)
        }
    }
}
