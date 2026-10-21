package com.codepup.openhiit_wear

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.Wearable
import kotlin.math.abs

/**
 * Measures how far the watch's clock is from the phone's, so cues and the
 * countdown run on the phone's time. Snapshots carry phone timestamps, and
 * the two clocks can differ by a few hundred milliseconds.
 *
 * Sends a few pings and keeps the reply with the shortest round trip, where
 * the estimate is most accurate (error is at most half the round trip).
 */
object ClockSync {
    private const val TAG = "OpenHiitWear"
    private const val PREFS = "openhiit_clock"
    private const val PINGS = 6
    private const val PING_GAP_MS = 250L

    /** Ignore offset changes smaller than this when deciding to reschedule. */
    private const val RESCHEDULE_THRESHOLD_MS = 15L

    /** Told about new offsets, so the open app can redraw on the new time. */
    @Volatile
    var onOffsetChanged: ((Long) -> Unit)? = null

    // Best round trip in the current round of pings.
    private var bestRoundTripMs = Long.MAX_VALUE

    /** Phone time minus watch time, from the last measurement (0 if none). */
    fun offsetMs(context: Context): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("offsetMs", 0)

    /** The current time on the phone's clock. */
    fun phoneNow(context: Context): Long = System.currentTimeMillis() + offsetMs(context)

    fun measure(context: Context) {
        val app = context.applicationContext
        bestRoundTripMs = Long.MAX_VALUE
        val handler = Handler(Looper.getMainLooper())
        Wearable.getNodeClient(app).connectedNodes.addOnSuccessListener { nodes ->
            val messages = Wearable.getMessageClient(app)
            for (i in 0 until PINGS) {
                handler.postDelayed({
                    val sentAt = System.currentTimeMillis().toString()
                    nodes.forEach {
                        messages.sendMessage(it.id, WearProtocol.PING_PATH, sentAt.toByteArray())
                    }
                }, i * PING_GAP_MS)
            }
        }
    }

    fun onPong(context: Context, data: ByteArray) {
        val receivedAt = System.currentTimeMillis()
        val parts = String(data).split(":")
        val sentAt = parts.getOrNull(0)?.toLongOrNull() ?: return
        val phoneAt = parts.getOrNull(1)?.toLongOrNull() ?: return
        val roundTrip = receivedAt - sentAt
        if (roundTrip < 0 || roundTrip >= bestRoundTripMs) {
            return
        }
        bestRoundTripMs = roundTrip
        val offset = phoneAt - (sentAt + receivedAt) / 2
        val previous = offsetMs(context)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong("offsetMs", offset).apply()
        Log.i(TAG, "Clock offset ${offset}ms (round trip ${roundTrip}ms)")

        if (abs(offset - previous) >= RESCHEDULE_THRESHOLD_MS) {
            onOffsetChanged?.invoke(offset)
            RunAlertService.reschedule(context)
        }
    }
}
