package com.codepup.openhiit_wear

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Runs when the phone publishes a run snapshot while the watch app is closed.
 *
 * Android blocks starting an activity from the background, so a new run posts
 * a notification that opens the app with one tap.
 */
class RunListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        val json = events
            .filter {
                it.type == DataEvent.TYPE_CHANGED &&
                    it.dataItem.uri.path == WearProtocol.RUN_PATH
            }
            .map { WearProtocol.json(it.dataItem) }
            .lastOrNull() ?: return

        val run = try {
            JSONObject(json)
        } catch (e: Exception) {
            return
        }

        if (!run.optBoolean("active")) {
            cancelNotification(this)
            return
        }

        if (MainActivity.isForeground) {
            return
        }

        // Only announce each run once, not on every interval change.
        val runId = run.optString("runId")
        val prefs = getSharedPreferences("openhiit_wear", Context.MODE_PRIVATE)
        if (prefs.getString("notifiedRunId", null) == runId) {
            return
        }
        prefs.edit().putString("notifiedRunId", runId).apply()
        showNotification(run.optString("name", "Timer"))
    }

    private fun showNotification(timerName: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Timer started on phone",
                NotificationManager.IMPORTANCE_HIGH,
            )
        )

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(timerName)
            .setContentText("Running on your phone. Tap to follow along.")
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // Notification permission not granted; the app still works when opened.
        }
    }

    companion object {
        private const val CHANNEL_ID = "run_started"
        private const val NOTIFICATION_ID = 1

        fun cancelNotification(context: Context) {
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        }
    }
}
