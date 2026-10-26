package com.twince.alarm

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.view.WindowManager
import android.widget.TextView
import java.util.Locale

/**
 * Full-screen alarm shown over the keyguard. The window uses
 * [WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED] and
 * [WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON], plus the Activity
 * equivalents on Android 8.1+.
 */
class AlarmRingActivity : android.app.Activity() {
    private lateinit var request: RingRequest

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
        consumeBack()
        setContentView(R.layout.activity_alarm_ring)
        bind(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlags()
        bind(intent)
    }

    @Deprecated("Back closes nothing while the alarm is ringing.")
    override fun onBackPressed() {
        // Require Dismiss, Restart, or Snooze.
    }

    private fun bind(source: Intent?) {
        request = RingRequest.fromIntent(source)
        val (time, period) = formatTime(this, request.hour, request.minute)
        findViewById<TextView>(R.id.timeText).text = time
        findViewById<TextView>(R.id.periodText).apply {
            text = period.orEmpty()
            visibility = if (period == null) android.view.View.GONE else android.view.View.VISIBLE
        }
        findViewById<TextView>(R.id.titleText).text = request.label
        findViewById<TextView>(R.id.subtitleText).text = request.subtitle
        findViewById<android.view.View>(R.id.dismissButton).setOnClickListener {
            act(AlarmRingService.ACTION_DISMISS, 0)
        }
        findViewById<android.view.View>(R.id.restartButton).setOnClickListener {
            act(AlarmRingService.ACTION_RESTART, 0)
        }
        findViewById<android.view.View>(R.id.snooze5).setOnClickListener {
            act(AlarmRingService.ACTION_SNOOZE, 5)
        }
        findViewById<android.view.View>(R.id.snooze10).setOnClickListener {
            act(AlarmRingService.ACTION_SNOOZE, 10)
        }
        if (request.token != 0L) {
            AlarmRingService.start(this, request)
        }
    }

    private fun act(action: String, minutes: Int) {
        val intent = request.serviceIntent(this, action, minutes)
        startService(intent)
        finish()
    }

    @Suppress("DEPRECATION")
    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        // Stay above the keyguard. Do not dismiss it.
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
    }

    private fun consumeBack() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            ) { }
        }
    }

    companion object {
        fun formatTime(context: Context, hour: Int, minute: Int): Pair<String, String?> {
            if (DateFormat.is24HourFormat(context)) {
                return String.format(Locale.US, "%02d:%02d", hour, minute) to null
            }
            val period = if (hour < 12) "AM" else "PM"
            val hour12 = when (val value = hour % 12) {
                0 -> 12
                else -> value
            }
            return String.format(Locale.US, "%02d:%02d", hour12, minute) to period
        }
    }
}
