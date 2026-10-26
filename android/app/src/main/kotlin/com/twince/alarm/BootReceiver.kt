package com.twince.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Restores exact alarms after reboot, upgrade, or a clock change. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i(AlarmContract.TAG, "Rescheduling alarms after ${intent.action}")
        try {
            AlarmScheduler.rescheduleAll(context)
        } catch (error: SecurityException) {
            Log.e(AlarmContract.TAG, "Exact alarm permission missing after ${intent.action}", error)
        }
    }
}
