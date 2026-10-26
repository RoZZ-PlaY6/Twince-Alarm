package com.twince.alarm

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Explicit broadcasts other apps can send to package `com.twince.alarm`.
 * The sender must declare `com.twince.alarm.permission.CONTROL_ALARMS`.
 *
 * ACTION_CREATE_ALARM extras:
 * - hour (int, 0-23, required)
 * - minute (int, 0-59, required)
 * - id (int, optional; updates that alarm when present)
 * - label (string, optional)
 * - subtitle (string, optional; default "Time to start your task")
 * - enabled (boolean, default true)
 * - vibrate (boolean, default true)
 * - soundUri (string, optional; empty uses the system alarm tone)
 * - repeatDays (int array, Monday=1 … Sunday=7, optional)
 *
 * ACTION_CANCEL_ALARM extras:
 * - id (int, required) or alarmId
 *
 * ACTION_REGISTER_CALLBACK extras:
 * - callbackPackage (string)
 * - callbackClass (string, fully qualified)
 * Later dismiss / snooze / restart events are sent explicitly to that component.
 *
 * Ordered-broadcast results: RESULT_OK and a JSON body, or RESULT_CANCELED.
 */
class AlarmCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                AlarmContract.ACTION_CREATE_ALARM -> create(context, intent)
                AlarmContract.ACTION_CANCEL_ALARM -> cancel(context, intent)
                AlarmContract.ACTION_REGISTER_CALLBACK -> register(context, intent)
                else -> setResult(Activity.RESULT_CANCELED, "unsupported", null)
            }
        } catch (error: IllegalArgumentException) {
            Log.w(AlarmContract.TAG, "Rejected alarm command", error)
            setResult(Activity.RESULT_CANCELED, error.message, null)
        } catch (error: Exception) {
            Log.e(AlarmContract.TAG, "Alarm command failed", error)
            setResult(Activity.RESULT_CANCELED, error.message, null)
        }
    }

    private fun create(context: Context, intent: Intent) {
        val hour = intent.getIntExtra(AlarmContract.EXTRA_HOUR, -1)
        val minute = intent.getIntExtra(AlarmContract.EXTRA_MINUTE, -1)
        require(hour in 0..23) { "hour must be 0..23" }
        require(minute in 0..59) { "minute must be 0..59" }
        val alarm = TwinceAlarm(
            id = if (intent.hasExtra("id")) {
                intent.getIntExtra("id", 0)
            } else {
                intent.getIntExtra(AlarmContract.EXTRA_ALARM_ID, 0)
            },
            hour = hour,
            minute = minute,
            label = intent.getStringExtra(AlarmContract.EXTRA_LABEL)?.trim().orEmpty().ifBlank { "Alarm" },
            subtitle = intent.getStringExtra(AlarmContract.EXTRA_SUBTITLE)?.trim().orEmpty()
                .ifBlank { AlarmContract.DEFAULT_SUBTITLE },
            enabled = intent.getBooleanExtra(AlarmContract.EXTRA_ENABLED, true),
            vibrate = intent.getBooleanExtra(AlarmContract.EXTRA_VIBRATE, true),
            soundUri = intent.getStringExtra(AlarmContract.EXTRA_SOUND_URI).orEmpty(),
            repeatDays = readDays(intent),
        )
        val saved = AlarmRepository.saveAndSchedule(context, alarm)
        val json = AlarmStore.toJson(saved.alarm).put("scheduleError", saved.scheduleError)
        setResult(Activity.RESULT_OK, json.toString(), null)
    }

    private fun cancel(context: Context, intent: Intent) {
        val id = when {
            intent.hasExtra(AlarmContract.EXTRA_ALARM_ID) ->
                intent.getIntExtra(AlarmContract.EXTRA_ALARM_ID, -1)
            intent.hasExtra("id") -> intent.getIntExtra("id", -1)
            else -> -1
        }
        require(id > 0) { "id is required" }
        AlarmRepository.delete(context, id)
        setResult(Activity.RESULT_OK, id.toString(), null)
    }

    private fun register(context: Context, intent: Intent) {
        val pkg = intent.getStringExtra(AlarmContract.EXTRA_CALLBACK_PACKAGE)?.trim().orEmpty()
        val cls = intent.getStringExtra(AlarmContract.EXTRA_CALLBACK_CLASS)?.trim().orEmpty()
        require(pkg.isNotEmpty() && cls.isNotEmpty()) { "callbackPackage and callbackClass are required" }
        AlarmStore.setCallbackComponent(context, pkg, cls)
        setResult(Activity.RESULT_OK, "$pkg/$cls", null)
    }

    private fun readDays(intent: Intent): List<Int> {
        intent.getIntArrayExtra(AlarmContract.EXTRA_REPEAT_DAYS)?.let {
            return sanitizeRepeatDays(it.toList())
        }
        intent.getIntegerArrayListExtra(AlarmContract.EXTRA_REPEAT_DAYS)?.let {
            return sanitizeRepeatDays(it)
        }
        val csv = intent.getStringExtra(AlarmContract.EXTRA_REPEAT_DAYS)
        if (!csv.isNullOrBlank()) {
            return sanitizeRepeatDays(csv.split(',').mapNotNull { it.trim().toIntOrNull() })
        }
        return emptyList()
    }
}
