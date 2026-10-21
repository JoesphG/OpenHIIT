package com.codepup.openhiit_wear

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** The watch's vibration cues for a run. */
object Haptics {
    /** Plays "tick" (3-2-1 countdown), "change" (next interval) or "done". */
    fun vibrate(context: Context, pattern: String) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val effect = when (pattern) {
            "tick" -> VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE)
            "done" -> VibrationEffect.createWaveform(longArrayOf(0, 300, 150, 300, 150, 600), -1)
            else -> VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        vibrator.vibrate(effect)
    }
}
