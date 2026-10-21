package com.codepup.openhiit_wear

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.ServiceCompat
import org.json.JSONObject

/**
 * Plays the run's countdown haptics and alert sounds on the watch, whether or
 * not the app is open.
 *
 * Each snapshot from the phone reschedules the cues from its interval
 * timings, so they stay in step with the phone's timer.
 */
class RunAlertService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var wakeLock: PowerManager.WakeLock
    private lateinit var sounds: SoundPool
    private val soundIds = mutableMapOf<String, Int>()
    private var lastRun: JSONObject? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        // Keep the CPU awake for the cues while the screen is off.
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "openhiit:run")
            .apply { setReferenceCounted(false) }
        sounds = SoundPool.Builder()
            .setMaxStreams(2)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    // The alarm stream stays audible mid-workout.
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val run = try {
            intent?.getStringExtra(EXTRA_JSON)?.let { JSONObject(it) }
        } catch (e: Exception) {
            null
        }

        // Must be called promptly after startForegroundService.
        ServiceCompat.startForeground(
            this,
            OngoingRun.NOTIFICATION_ID,
            OngoingRun.build(this, run ?: lastRun ?: JSONObject()),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            },
        )

        if (intent?.action == ACTION_RESCHEDULE) {
            lastRun?.let { schedule(it) }
            return START_NOT_STICKY
        }
        if (run == null || !run.optBoolean("active")) {
            stopSelf()
        } else {
            lastRun = run
            schedule(run)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        sounds.release()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun schedule(run: JSONObject) {
        handler.removeCallbacksAndMessages(null)
        val intervals = run.optJSONArray("intervals") ?: return
        if (run.optBoolean("paused") || intervals.length() == 0) {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
            return
        }

        for (i in 0 until intervals.length()) {
            val interval = intervals.getJSONObject(i)
            listOf("startSound", "countdownSound", "endSound").forEach {
                preload(interval.optString(it))
            }
        }

        // Snapshot times are on the phone's clock, so schedule on it too.
        val now = ClockSync.phoneNow(this)
        // End of the current interval, on the phone's clock, moved to when
        // the phone's sounds are actually heard.
        var boundary = run.optLong("sentAt") + run.optLong("remainingMs") +
            PHONE_SOUND_DELAY_MS
        val last = intervals.length() - 1
        for (k in run.optInt("index")..last) {
            val interval = intervals.getJSONObject(k)
            // Same offsets as the phone's timer, which plays its cues early so
            // they land on time despite audio latency.
            if (interval.optLong("seconds") >= 4) {
                for (offset in COUNTDOWN_OFFSETS_MS) {
                    at(boundary - offset, now) {
                        Haptics.vibrate(this, "tick")
                        play(interval.optString("countdownSound"))
                    }
                }
            }
            if (k == last) {
                at(boundary - START_OFFSET_MS, now) {
                    Haptics.vibrate(this, "done")
                    play(interval.optString("endSound"))
                }
            } else {
                val next = intervals.getJSONObject(k + 1)
                at(boundary - START_OFFSET_MS, now) {
                    Haptics.vibrate(this, "change")
                    play(next.optString("startSound").ifEmpty { interval.optString("endSound") })
                }
                boundary += next.optLong("seconds") * 1000
            }
        }
        wakeLock.acquire((boundary - now).coerceAtLeast(0) + WAKE_GRACE_MS)
    }

    private fun at(wallTime: Long, now: Long, cue: () -> Unit) {
        val delay = wallTime - now
        if (delay >= 0) {
            handler.postDelayed(cue, delay)
        }
    }

    private fun preload(name: String) {
        if (name.isEmpty() || name == "none" || soundIds.containsKey(name)) {
            return
        }
        val resId = resources.getIdentifier(name.replace('-', '_'), "raw", packageName)
        if (resId != 0) {
            soundIds[name] = sounds.load(this, resId, 1)
        }
    }

    private fun play(name: String) {
        soundIds[name]?.let { sounds.play(it, 1f, 1f, 1, 0, 1f) }
    }

    companion object {
        const val EXTRA_JSON = "json"

        @Volatile
        private var running = false
        private const val ACTION_RESCHEDULE = "reschedule"

        /** Re-times the cues after the clock offset changes, if running. */
        fun reschedule(context: android.content.Context) {
            if (!running) {
                return
            }
            try {
                context.startService(
                    Intent(context, RunAlertService::class.java).setAction(ACTION_RESCHEDULE)
                )
            } catch (e: Exception) {
                // Not running; the next snapshot schedules with the new offset.
            }
        }

        // Matches background_hiit_timer: countdown at 3.5/2.5/1.5s left and
        // the next interval's start sound at 0.7s left.
        private val COUNTDOWN_OFFSETS_MS = longArrayOf(3500, 2500, 1500)
        private const val START_OFFSET_MS = 700L

        // The phone starts playing each cue about this long after its timer
        // reaches it (measured on a Pixel 10 Pro XL), so match the sound.
        private const val PHONE_SOUND_DELAY_MS = 120L
        private const val WAKE_GRACE_MS = 30_000L
    }
}
