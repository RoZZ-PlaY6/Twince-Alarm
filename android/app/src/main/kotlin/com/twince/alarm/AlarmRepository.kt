package com.twince.alarm

import android.content.Context

data class SaveResult(
    val alarm: TwinceAlarm,
    val scheduleError: String,
)

/** Saves an alarm and mirrors it into AlarmManager. Shared by Flutter and IPC. */
object AlarmRepository {
    fun saveAndSchedule(context: Context, alarm: TwinceAlarm): SaveResult {
        val saved = AlarmStore.upsert(context, alarm)
        val error = try {
            AlarmScheduler.cancelSnooze(context, saved.id)
            if (saved.enabled) {
                AlarmScheduler.schedule(context, saved)
            } else {
                AlarmScheduler.cancelMain(context, saved.id)
            }
            ""
        } catch (error: SecurityException) {
            android.util.Log.e(AlarmContract.TAG, "Exact alarm denied", error)
            "exact_alarm"
        }
        return SaveResult(saved, error)
    }

    fun delete(context: Context, id: Int) {
        AlarmScheduler.cancelAll(context, id)
        AlarmStore.delete(context, id)
    }

    fun setEnabled(context: Context, id: Int, enabled: Boolean): SaveResult? {
        val existing = AlarmStore.find(context, id) ?: return null
        return saveAndSchedule(context, existing.copy(enabled = enabled))
    }
}
