package com.twince.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

/**
 * Fired by [android.app.AlarmManager.setAlarmClock]. Starts the ringing
 * foreground service, which turns the screen on and shows the lock-screen UI.
 */
class AlarmFireReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(AlarmContract.EXTRA_ALARM_ID, -1)
        if (alarmId < 0) return
        val snooze = intent.getBooleanExtra(AlarmContract.EXTRA_SNOOZE, false)
        val alarm = AlarmStore.find(context, alarmId)
        if (alarm == null) {
            Log.w(AlarmContract.TAG, "Ignoring fire for missing alarm $alarmId")
            return
        }

        val power = context.getSystemService(PowerManager::class.java)
        val wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "twince:alarm-fire")
        wakeLock.acquire(20_000L)
        try {
            if (!snooze) {
                try {
                    if (alarm.repeatDays.isEmpty()) {
                        AlarmStore.upsert(context, alarm.copy(enabled = false))
                        AlarmScheduler.cancelMain(context, alarm.id)
                    } else {
                        // The pending intent that just fired is replaced with the next occurrence.
                        AlarmScheduler.schedule(context, alarm)
                    }
                } catch (error: SecurityException) {
                    Log.e(AlarmContract.TAG, "Could not roll the alarm forward", error)
                }
            }
            val request = RingRequest(
                alarmId = alarm.id,
                hour = alarm.hour,
                minute = alarm.minute,
                label = alarm.label,
                subtitle = alarm.subtitle,
                vibrate = alarm.vibrate,
                soundUri = alarm.soundUri,
                preview = false,
                token = System.currentTimeMillis(),
            )
            AlarmRingService.start(context, request)
        } catch (error: Exception) {
            Log.e(AlarmContract.TAG, "Failed to start ringing", error)
        } finally {
            if (wakeLock.isHeld) wakeLock.release()
        }
    }
}
