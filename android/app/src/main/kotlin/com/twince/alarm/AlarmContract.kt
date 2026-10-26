package com.twince.alarm

import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Shared actions, permissions, and extras for Twince Alarm.
 *
 * Other apps (such as Twince) can create and cancel alarms by sending an
 * explicit broadcast to package `com.twince.alarm`. The sender must declare
 * `com.twince.alarm.permission.CONTROL_ALARMS`.
 *
 * Outcomes are reported in-process through [AlarmCallbacks] and to other
 * processes as [ACTION_ALARM_EVENT]. A manifest receiver on Android 8+ only
 * receives that callback when this app has an explicit component registered
 * via [ACTION_REGISTER_CALLBACK]. Listeners must hold
 * [PERMISSION_LISTEN].
 */
object AlarmContract {
    const val TAG = "TwinceAlarm"

    const val ACTION_CREATE_ALARM = "com.twince.alarm.ACTION_CREATE_ALARM"
    const val ACTION_CANCEL_ALARM = "com.twince.alarm.ACTION_CANCEL_ALARM"
    const val ACTION_REGISTER_CALLBACK = "com.twince.alarm.ACTION_REGISTER_CALLBACK"
    const val ACTION_ALARM_EVENT = "com.twince.alarm.ACTION_ALARM_EVENT"
    const val ACTION_FIRE = "com.twince.alarm.ACTION_FIRE"

    const val PERMISSION_CONTROL = "com.twince.alarm.permission.CONTROL_ALARMS"
    const val PERMISSION_LISTEN = "com.twince.alarm.permission.LISTEN_ALARM_EVENTS"

    const val EXTRA_ALARM_ID = "alarmId"
    const val EXTRA_HOUR = "hour"
    const val EXTRA_MINUTE = "minute"
    const val EXTRA_LABEL = "label"
    const val EXTRA_SUBTITLE = "subtitle"
    const val EXTRA_ENABLED = "enabled"
    const val EXTRA_VIBRATE = "vibrate"
    const val EXTRA_SOUND_URI = "soundUri"
    const val EXTRA_REPEAT_DAYS = "repeatDays"
    const val EXTRA_SNOOZE = "snooze"
    const val EXTRA_SNOOZE_MINUTES = "snoozeMinutes"
    const val EXTRA_PREVIEW = "preview"
    const val EXTRA_TOKEN = "token"
    const val EXTRA_EVENT = "event"
    const val EXTRA_CALLBACK_PACKAGE = "callbackPackage"
    const val EXTRA_CALLBACK_CLASS = "callbackClass"
    const val EXTRA_AT = "at"

    const val EVENT_DISMISS = "dismiss"
    const val EVENT_SNOOZE = "snooze"
    const val EVENT_RESTART = "restart"

    const val DEFAULT_SUBTITLE = "Time to start your task"
    const val CHANNEL_ID = "twince_alarm_ring"
    const val NOTIFICATION_ID = 4101

    const val SNOOZE_REQUEST_OFFSET = 1_000_000
    const val SHOW_REQUEST_OFFSET = 2_000_000

    val PI_FLAGS: Int =
        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
}

/** Monday = 1 … Sunday = 7, matching Dart's DateTime.weekday. */
fun calendarDayToIso(calendarDay: Int): Int {
    return if (calendarDay == Calendar.SUNDAY) 7 else calendarDay - 1
}

fun sanitizeRepeatDays(days: Collection<Int>): List<Int> {
    return days.filter { it in 1..7 }.distinct().sorted()
}

data class RingRequest(
    val alarmId: Int,
    val hour: Int,
    val minute: Int,
    val label: String,
    val subtitle: String,
    val vibrate: Boolean,
    val soundUri: String,
    val preview: Boolean,
    val token: Long,
) {
    fun fillIntent(intent: Intent): Intent {
        return intent.apply {
            putExtra(AlarmContract.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmContract.EXTRA_HOUR, hour)
            putExtra(AlarmContract.EXTRA_MINUTE, minute)
            putExtra(AlarmContract.EXTRA_LABEL, label)
            putExtra(AlarmContract.EXTRA_SUBTITLE, subtitle)
            putExtra(AlarmContract.EXTRA_VIBRATE, vibrate)
            putExtra(AlarmContract.EXTRA_SOUND_URI, soundUri)
            putExtra(AlarmContract.EXTRA_PREVIEW, preview)
            putExtra(AlarmContract.EXTRA_TOKEN, token)
        }
    }

    fun serviceIntent(context: Context, action: String, snoozeMinutes: Int = 0): Intent {
        return fillIntent(Intent(context, AlarmRingService::class.java)).apply {
            this.action = action
            if (snoozeMinutes > 0) {
                putExtra(AlarmContract.EXTRA_SNOOZE_MINUTES, snoozeMinutes)
            }
        }
    }

    companion object {
        fun fromIntent(intent: Intent?): RingRequest {
            val src = intent ?: Intent()
            val rawLabel = src.getStringExtra(AlarmContract.EXTRA_LABEL)?.trim().orEmpty()
            val rawSubtitle = src.getStringExtra(AlarmContract.EXTRA_SUBTITLE)?.trim().orEmpty()
            return RingRequest(
                alarmId = src.getIntExtra(AlarmContract.EXTRA_ALARM_ID, 0),
                hour = src.getIntExtra(AlarmContract.EXTRA_HOUR, 7).coerceIn(0, 23),
                minute = src.getIntExtra(AlarmContract.EXTRA_MINUTE, 30).coerceIn(0, 59),
                label = rawLabel.ifBlank { "Morning workout" },
                subtitle = rawSubtitle.ifBlank { AlarmContract.DEFAULT_SUBTITLE },
                vibrate = if (src.hasExtra(AlarmContract.EXTRA_VIBRATE)) {
                    src.getBooleanExtra(AlarmContract.EXTRA_VIBRATE, true)
                } else {
                    true
                },
                soundUri = src.getStringExtra(AlarmContract.EXTRA_SOUND_URI).orEmpty(),
                preview = src.getBooleanExtra(AlarmContract.EXTRA_PREVIEW, false),
                token = src.getLongExtra(AlarmContract.EXTRA_TOKEN, 0L),
            )
        }
    }
}
