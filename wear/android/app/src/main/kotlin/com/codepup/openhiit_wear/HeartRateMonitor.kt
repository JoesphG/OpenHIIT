package com.codepup.openhiit_wear

import android.content.Context
import android.util.Log
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType

/**
 * Streams live heart rate from Health Services while started.
 *
 * Uses the measure API, which only runs while the app is in the foreground,
 * so it costs no battery when the watch app isn't open.
 */
class HeartRateMonitor(context: Context, private val onBpm: (Double) -> Unit) {
    private val measureClient = HealthServices.getClient(context).measureClient
    private var registered = false

    private val callback = object : MeasureCallback {
        override fun onAvailabilityChanged(
            dataType: DeltaDataType<*, *>,
            availability: Availability,
        ) {
        }

        override fun onDataReceived(data: DataPointContainer) {
            data.getData(DataType.HEART_RATE_BPM).lastOrNull()?.let { point ->
                if (point.value > 0) {
                    onBpm(point.value)
                }
            }
        }
    }

    fun start() {
        if (registered) {
            return
        }
        try {
            measureClient.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
            registered = true
        } catch (e: Throwable) {
            // Heart rate is optional; never let a sensor problem stop the timer.
            Log.w(TAG, "Heart rate unavailable", e)
        }
    }

    fun stop() {
        if (!registered) {
            return
        }
        registered = false
        try {
            measureClient.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
        } catch (e: Throwable) {
            Log.w(TAG, "Couldn't stop heart rate", e)
        }
    }

    companion object {
        private const val TAG = "HeartRateMonitor"
    }
}
