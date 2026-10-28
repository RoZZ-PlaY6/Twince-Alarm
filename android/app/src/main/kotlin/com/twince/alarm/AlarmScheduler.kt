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
        val trigger = triggerFor(context, alarm) ?: run {
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

    private fun triggerFor(
        context: Context,
        alarm: TwinceAlarm,
        fromMillis: Long = System.currentTimeMillis(),
    ): Long? {
        val config = loadWeekConfig(context)
        return nextTriggerMillis(alarm, fromMillis, config.cycle, config.legacyMapping)
    }

    private fun nextTriggerMillis(
        alarm: TwinceAlarm,
        fromMillis: Long = System.currentTimeMillis(),
        cycle: WeekCycle? = null,
        legacyMapping: Boolean = false,
    ): Long? {
        if (!alarm.enabled) return null
        if (alarm.repeatDays.isEmpty() && alarm.weekTags.isEmpty()) {
            val cal = atTime(fromMillis, alarm.hour, alarm.minute)
            if (cal.timeInMillis <= fromMillis) cal.add(Calendar.DAY_OF_YEAR, 1)
            return cal.timeInMillis
        }
        val wanted = alarm.repeatDays.toSet()
        val limit = if (needsWeekFilter(alarm.weekTags)) 21 else 7
        for (offset in 0..limit) {
            val cal = atTime(fromMillis, alarm.hour, alarm.minute)
            cal.add(Calendar.DAY_OF_YEAR, offset)
            val iso = if (wanted.isEmpty()) 0 else calendarDayToIso(cal.get(Calendar.DAY_OF_WEEK))
            val dayMatches = wanted.isEmpty() || iso in wanted
            if (dayMatches && weekAllowed(cal, alarm.weekTags, cycle, legacyMapping) && cal.timeInMillis > fromMillis) {
                return cal.timeInMillis
            }
        }
        return null
    }

    private fun needsWeekFilter(tags: List<String>): Boolean {
        val kind = recurrenceKind(tags)
        return kind == "Z" || kind == "F"
    }

    // Empty tags are manual alarms. "both" runs every Saturday-Friday week.
    // Z is the even week and F is the odd week chosen by the user.
    private fun weekAllowed(
        cal: Calendar,
        tags: List<String>,
        cycle: WeekCycle?,
        legacyMapping: Boolean,
    ): Boolean {
        return when (recurrenceKind(tags)) {
            "manual" -> true
            // Every-week plans do not depend on the user's Z/F anchor.
            // They must remain schedulable even before a parity choice exists.
            "both" -> true
            "Z" -> cycle != null && if (legacyMapping) !isEvenWeek(cycle, cal) else isEvenWeek(cycle, cal)
            "F" -> cycle != null && if (legacyMapping) isEvenWeek(cycle, cal) else !isEvenWeek(cycle, cal)
            else -> false
        }
    }

    private fun recurrenceKind(tags: List<String>): String {
        val normalized = tags.map { it.trim().lowercase() }.toSet()
        if (normalized.isEmpty()) return "manual"
        if (normalized == setOf("both") || normalized == setOf("every")) return "both"
        if (normalized == setOf("z", "f")) return "both"
        if (normalized == setOf("z") || normalized == setOf("even")) return "Z"
        if (normalized == setOf("f") || normalized == setOf("odd")) return "F"
        return "unknown"
    }

    private fun isEvenWeek(cycle: WeekCycle, cal: Calendar): Boolean {
        val anchor = saturdayOnOrBefore(cycle.year, cycle.month, cycle.day)
        val current = saturdayOnOrBefore(
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
        val days = utcDaysBetween(anchor, current)
        val flipped = kotlin.math.abs(days / 7) % 2 != 0
        return if (flipped) !cycle.even else cycle.even
    }

    private fun saturdayOnOrBefore(year: Int, month: Int, day: Int): IntArray {
        val cal = utcNoon(year, month, day)
        val weekday = calendarDayToIso(cal.get(Calendar.DAY_OF_WEEK))
        cal.add(Calendar.DAY_OF_MONTH, -((weekday + 1) % 7))
        return intArrayOf(
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
    }

    private fun utcDaysBetween(start: IntArray, end: IntArray): Int {
        val a = utcNoon(start[0], start[1], start[2]).timeInMillis
        val b = utcNoon(end[0], end[1], end[2]).timeInMillis
        return ((b - a) / 86_400_000L).toInt()
    }

    private fun utcNoon(year: Int, month: Int, day: Int): Calendar {
        return Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun loadWeekConfig(context: Context): WeekConfig {
        val raw = AlarmStore.loadPlanLibrary(context)
        if (raw.isBlank()) return WeekConfig(null, false)
        return try {
            val root = org.json.JSONObject(raw)
            val cycle = root.optJSONObject("weekCycle") ?: return WeekConfig(null, root.optInt("weekParityMapping", 1) != 2)
            if (!cycle.has("even")) return WeekConfig(null, root.optInt("weekParityMapping", 1) != 2)
            val parts = cycle.optString("anchorSaturday").split("-")
            if (parts.size != 3) return WeekConfig(null, root.optInt("weekParityMapping", 1) != 2)
            WeekConfig(
                WeekCycle(parts[0].toInt(), parts[1].toInt(), parts[2].toInt(), cycle.getBoolean("even")),
                root.optInt("weekParityMapping", 1) != 2,
            )
        } catch (_: Exception) {
            WeekConfig(null, false)
        }
    }

    private data class WeekConfig(val cycle: WeekCycle?, val legacyMapping: Boolean)
    private data class WeekCycle(val year: Int, val month: Int, val day: Int, val even: Boolean)

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
