package com.twince.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.util.Calendar

object AlarmScheduler {
    fun canScheduleExact(context: Context): Boolean {
        val manager = alarmManager(context)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun rescheduleAll(context: Context) {
        val app = context.applicationContext
        if (!canScheduleExact(app)) {
            Log.w(AlarmContract.TAG, "Exact alarms are not allowed; active alarms stay saved but unscheduled")
            return
        }
        for (alarm in AlarmStore.getAlarms(app)) {
            if (alarm.enabled) {
                schedule(app, alarm)
            } else {
                cancelMain(app, alarm.id)
            }
        }
        val now = System.currentTimeMillis()
        for (snooze in AlarmStore.getSnoozes(app)) {
            val alarm = AlarmStore.find(app, snooze.alarmId)
            if (alarm == null) {
                AlarmStore.clearSnooze(app, snooze.alarmId)
                continue
            }
            if (snooze.triggerAt <= now - 60_000L) {
                AlarmStore.clearSnooze(app, snooze.alarmId)
                cancelSnooze(app, snooze.alarmId)
            } else {
                val whenAt = maxOf(snooze.triggerAt, now + 1_000L)
                scheduleSnoozeAt(app, alarm, whenAt)
            }
        }
    }

    fun schedule(context: Context, alarm: TwinceAlarm) {
        val app = context.applicationContext
        val manager = alarmManager(app)
        val operation = firePending(app, alarm.id, snooze = false)
        if (!alarm.enabled) {
            manager.cancel(operation)
            return
        }
        val trigger = nextTriggerMillis(alarm) ?: run {
            manager.cancel(operation)
            return
        }
        val info = AlarmManager.AlarmClockInfo(trigger, showPending(app, alarm.id))
        // setAlarmClock is the user-visible alarm API: it wakes from Doze and
        // is eligible to present a full-screen alarm over the lock screen.
        manager.setAlarmClock(info, operation)
        Log.i(AlarmContract.TAG, "Scheduled alarm ${alarm.id} at $trigger")
    }

    fun scheduleSnooze(context: Context, alarm: TwinceAlarm, minutes: Int) {
        val trigger = System.currentTimeMillis() + minutes.coerceAtLeast(1) * 60_000L
        scheduleSnoozeAt(context, alarm, trigger)
    }

    fun scheduleSnoozeAt(context: Context, alarm: TwinceAlarm, triggerAt: Long) {
        val app = context.applicationContext
        AlarmStore.setSnooze(app, alarm.id, triggerAt)
        val info = AlarmManager.AlarmClockInfo(triggerAt, showPending(app, alarm.id))
        alarmManager(app).setAlarmClock(info, firePending(app, alarm.id, snooze = true))
        Log.i(AlarmContract.TAG, "Snoozed alarm ${alarm.id} until $triggerAt")
    }

    fun cancelMain(context: Context, alarmId: Int) {
        alarmManager(context).cancel(firePending(context.applicationContext, alarmId, snooze = false))
    }

    fun cancelSnooze(context: Context, alarmId: Int) {
        val app = context.applicationContext
        alarmManager(app).cancel(firePending(app, alarmId, snooze = true))
        AlarmStore.clearSnooze(app, alarmId)
    }

    fun cancelAll(context: Context, alarmId: Int) {
        cancelMain(context, alarmId)
        cancelSnooze(context, alarmId)
    }

    fun nextTriggerMillis(alarm: TwinceAlarm, fromMillis: Long = System.currentTimeMillis()): Long? {
        if (!alarm.enabled) return null
        if (alarm.repeatDays.isEmpty()) {
            val cal = atTime(fromMillis, alarm.hour, alarm.minute)
            if (cal.timeInMillis <= fromMillis) cal.add(Calendar.DAY_OF_YEAR, 1)
            return cal.timeInMillis
        }
        val wanted = alarm.repeatDays.toSet()
        val limit = if (needsWeekFilter(alarm.weekTags)) 21 else 7
        for (offset in 0..limit) {
            val cal = atTime(fromMillis, alarm.hour, alarm.minute)
            cal.add(Calendar.DAY_OF_YEAR, offset)
            val iso = calendarDayToIso(cal.get(Calendar.DAY_OF_WEEK))
            if (iso in wanted && weekAllowed(cal, alarm.weekTags) && cal.timeInMillis > fromMillis) {
                return cal.timeInMillis
            }
        }
        return null
    }

    private fun needsWeekFilter(tags: List<String>): Boolean {
        val wanted = tags.map { it.uppercase() }.filter { it == "Z" || it == "F" }.toSet()
        return wanted.size == 1
    }

    // Odd ISO-8601 weeks are Z. Even ISO-8601 weeks are F.
    // Manual alarms have no week tags and keep the previous schedule.
    private fun weekAllowed(cal: Calendar, tags: List<String>): Boolean {
        if (!needsWeekFilter(tags)) return true
        val odd = isoWeekNumber(cal) % 2 == 1
        val label = if (odd) "Z" else "F"
        return tags.any { it.equals(label, ignoreCase = true) }
    }

    private fun isoWeekNumber(source: Calendar): Int {
        val copy = source.clone() as Calendar
        copy.set(Calendar.HOUR_OF_DAY, 12)
        copy.set(Calendar.MINUTE, 0)
        copy.set(Calendar.SECOND, 0)
        copy.set(Calendar.MILLISECOND, 0)
        val weekday = calendarDayToIso(copy.get(Calendar.DAY_OF_WEEK))
        copy.add(Calendar.DAY_OF_YEAR, 4 - weekday)
        val dayOfYear = copy.get(Calendar.DAY_OF_YEAR)
        return ((dayOfYear - 1) / 7) + 1
    }

    private fun atTime(fromMillis: Long, hour: Int, minute: Int): Calendar {
        return Calendar.getInstance().apply {
            timeInMillis = fromMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun firePending(context: Context, alarmId: Int, snooze: Boolean): PendingIntent {
        val intent = Intent(context, AlarmFireReceiver::class.java).apply {
            action = AlarmContract.ACTION_FIRE
            data = Uri.parse("twince://alarm/$alarmId?snooze=$snooze")
            putExtra(AlarmContract.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmContract.EXTRA_SNOOZE, snooze)
        }
        val request = if (snooze) alarmId + AlarmContract.SNOOZE_REQUEST_OFFSET else alarmId
        return PendingIntent.getBroadcast(context, request, intent, AlarmContract.PI_FLAGS)
    }

    private fun showPending(context: Context, alarmId: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data = Uri.parse("twince://alarm/$alarmId/show")
            putExtra(AlarmContract.EXTRA_ALARM_ID, alarmId)
        }
        return PendingIntent.getActivity(
            context,
            alarmId + AlarmContract.SHOW_REQUEST_OFFSET,
            intent,
            AlarmContract.PI_FLAGS,
        )
    }

    private fun alarmManager(context: Context): AlarmManager {
        return context.applicationContext.getSystemService(AlarmManager::class.java)
    }
}
