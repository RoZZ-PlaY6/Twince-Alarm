package com.twince.alarm

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * In-process hooks. Replace these lambdas to observe alarm outcomes inside
 * this process. The defaults log the call. Work (stopping audio, scheduling a
 * snooze) is done by [AlarmRingService] before these run.
 *
 * Cross-process listeners receive [AlarmContract.ACTION_ALARM_EVENT]:
 * - event: "dismiss" | "snooze" | "restart"
 * - alarmId: Int
 * - snoozeMinutes: Int (0 unless event is snooze)
 * - label: String
 * - at: Long epoch millis
 *
 * onDismiss(alarmId), onSnooze(alarmId, durationMinutes), onRestart(alarmId).
 */
object AlarmCallbacks {
    var onDismiss: (alarmId: Int) -> Unit = { alarmId ->
        Log.i(AlarmContract.TAG, "onDismiss alarmId=$alarmId")
    }

    var onSnooze: (alarmId: Int, durationMinutes: Int) -> Unit = { alarmId, minutes ->
        Log.i(AlarmContract.TAG, "onSnooze alarmId=$alarmId durationMinutes=$minutes")
    }

    var onRestart: (alarmId: Int) -> Unit = { alarmId ->
        Log.i(AlarmContract.TAG, "onRestart alarmId=$alarmId")
    }

    fun invoke(type: String, alarmId: Int, snoozeMinutes: Int) {
        try {
            when (type) {
                AlarmContract.EVENT_DISMISS -> onDismiss(alarmId)
                AlarmContract.EVENT_SNOOZE -> onSnooze(alarmId, snoozeMinutes)
                AlarmContract.EVENT_RESTART -> onRestart(alarmId)
            }
        } catch (error: Throwable) {
            Log.e(AlarmContract.TAG, "Alarm callback failed for $type", error)
        }
    }
}

object AlarmEvents {
    @Volatile
    var sink: EventChannel.EventSink? = null

    private val main = Handler(Looper.getMainLooper())

    fun publish(
        context: Context,
        type: String,
        alarmId: Int,
        snoozeMinutes: Int,
        label: String,
    ) {
        val app = context.applicationContext
        val payload = hashMapOf<String, Any?>(
            "event" to type,
            "type" to type,
            "alarmId" to alarmId,
            "snoozeMinutes" to snoozeMinutes,
            "label" to label,
            "at" to System.currentTimeMillis(),
        )
        AlarmCallbacks.invoke(type, alarmId, snoozeMinutes)
        sendBroadcasts(app, payload)
        val active = sink
        if (active != null) {
            main.post {
                try {
                    active.success(payload)
                } catch (error: Throwable) {
                    Log.w(AlarmContract.TAG, "Flutter event sink unavailable", error)
                    AlarmStore.appendEvent(app, payload)
                }
            }
        } else {
            AlarmStore.appendEvent(app, payload)
        }
    }

    private fun sendBroadcasts(context: Context, payload: Map<String, Any?>) {
        val implicit = Intent(AlarmContract.ACTION_ALARM_EVENT).apply { putPayload(payload) }
        context.sendBroadcast(implicit, AlarmContract.PERMISSION_LISTEN)

        val component = AlarmStore.callbackComponent(context) ?: return
        val explicit = Intent(AlarmContract.ACTION_ALARM_EVENT).apply {
            this.component = component
            putPayload(payload)
        }
        context.sendBroadcast(explicit)
    }

    private fun Intent.putPayload(payload: Map<String, Any?>) {
        putExtra(AlarmContract.EXTRA_EVENT, payload["event"] as? String ?: "")
        putExtra(AlarmContract.EXTRA_ALARM_ID, payload["alarmId"] as? Int ?: 0)
        putExtra(AlarmContract.EXTRA_SNOOZE_MINUTES, payload["snoozeMinutes"] as? Int ?: 0)
        putExtra(AlarmContract.EXTRA_LABEL, payload["label"] as? String ?: "")
        putExtra(AlarmContract.EXTRA_AT, payload["at"] as? Long ?: 0L)
    }
}
