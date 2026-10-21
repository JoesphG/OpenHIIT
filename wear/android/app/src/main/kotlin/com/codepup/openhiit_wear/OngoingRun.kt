package com.codepup.openhiit_wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import org.json.JSONObject

/**
 * Keeps an Ongoing Activity up while the phone is running a timer, so the
 * OpenHIIT icon sits on the watch face and in recents to get back into the run.
 *
 * [RunAlertService] shows it while running; [update] posts it directly when
 * the service can't start.
 */
object OngoingRun {
    private const val CHANNEL_ID = "run_active"
    const val NOTIFICATION_ID = 1

    // Remove the icon this long after the run should have ended, in case the
    // phone app closed without saying so.
    private const val END_GRACE_MS = 60_000L

    fun update(context: Context, json: String?) {
        val run = try {
            json?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }
        if (run == null || !run.optBoolean("active")) {
            cancel(context)
            return
        }
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, build(context, run))
        } catch (e: SecurityException) {
            // Notification permission not granted; the app still works when opened.
        }
    }

    fun cancel(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Builds the run notification, with the Ongoing Activity attached. */
    fun build(context: Context, run: JSONObject): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Active timer", NotificationManager.IMPORTANCE_HIGH)
        )

        // Alert once when a run starts on the phone, then update silently.
        val runId = run.optString("runId")
        val prefs = context.getSharedPreferences("openhiit_wear", Context.MODE_PRIVATE)
        val isNewRun = prefs.getString("notifiedRunId", null) != runId
        if (isNewRun) {
            prefs.edit().putString("notifiedRunId", runId).apply()
        }
        val alert = isNewRun && !MainActivity.isForeground

        val paused = run.optBoolean("paused")
        val remainingMs = remainingRunMs(context, run)
        // Status timers count on the elapsedRealtime clock.
        val endsAt = SystemClock.elapsedRealtime() + remainingMs

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val name = run.optString("name", "Timer")
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(name)
            .setContentText(if (paused) "Paused on your phone" else "Running on your phone")
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(!alert)
        if (!paused) {
            builder.setTimeoutAfter(remainingMs + END_GRACE_MS)
        }

        val status = Status.Builder()
            .addTemplate(if (paused) "$name · paused" else "$name · #left# left")
            .addPart(
                "left",
                if (paused) {
                    Status.TimerPart(endsAt, SystemClock.elapsedRealtime())
                } else {
                    Status.TimerPart(endsAt)
                },
            )
            .build()

        OngoingActivity.Builder(context, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_launcher_monochrome)
            .setTouchIntent(open)
            .setStatus(status)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .build()
            .apply(context)

        return builder.build()
    }

    /** Time left in the whole run, counted on from when the phone sent it. */
    private fun remainingRunMs(context: Context, run: JSONObject): Long {
        val intervals = run.optJSONArray("intervals") ?: return 0
        val index = run.optInt("index")
        var remaining = run.optLong("remainingMs")
        for (i in index + 1 until intervals.length()) {
            remaining += intervals.getJSONObject(i).optLong("seconds") * 1000
        }
        if (!run.optBoolean("paused")) {
            val sinceSent = ClockSync.phoneNow(context) - run.optLong("sentAt")
            remaining -= sinceSent.coerceAtLeast(0)
        }
        return remaining.coerceAtLeast(0)
    }
}
