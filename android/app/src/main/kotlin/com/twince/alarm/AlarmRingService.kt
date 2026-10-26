package com.twince.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * Plays the alarm tone from the foreground so audio continues if the
 * full-screen activity is covered, and posts the full-screen intent that
 * shows [AlarmRingActivity] over the keyguard.
 */
class AlarmRingService : Service() {
    private val player by lazy { AlarmSoundPlayer(this) }
    private val main = Handler(Looper.getMainLooper())
    private var partialWake: PowerManager.WakeLock? = null
    private var screenWake: PowerManager.WakeLock? = null
    private var activeToken = 0L
    private var activeRequest: RingRequest? = null
    private var foreground = false

    private val autoStop = Runnable {
        val request = activeRequest ?: return@Runnable
        complete(AlarmContract.EVENT_DISMISS, request, 0)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        if (action != ACTION_START) {
            val request = activeRequest ?: RingRequest.fromIntent(intent)
            val minutes = intent?.getIntExtra(AlarmContract.EXTRA_SNOOZE_MINUTES, 0) ?: 0
            complete(actionToEvent(action), request, minutes)
            return START_NOT_STICKY
        }

        val request = RingRequest.fromIntent(intent)
        // Every foreground start must call startForeground, including duplicates.
        promote(buildNotification(request))
        if (request.token != 0L && request.token == activeToken) {
            return START_STICKY
        }
        activeToken = request.token
        activeRequest = request
        holdWakes()
        player.start(request.soundUri, request.vibrate)
        launchActivity(request)
        main.removeCallbacks(autoStop)
        main.postDelayed(autoStop, RING_TIMEOUT_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        main.removeCallbacks(autoStop)
        player.stop()
        releaseWakes()
        super.onDestroy()
    }

    private fun complete(event: String, request: RingRequest, snoozeMinutes: Int) {
        main.removeCallbacks(autoStop)
        player.stop()
        releaseWakes()
        activeToken = 0L
        activeRequest = null
        try {
            when (event) {
                AlarmContract.EVENT_SNOOZE -> {
                    if (request.alarmId > 0 && snoozeMinutes > 0) {
                        val stored = AlarmStore.find(this, request.alarmId)
                        if (stored != null) {
                            AlarmScheduler.scheduleSnooze(this, stored, snoozeMinutes)
                        }
                    }
                }
                else -> {
                    if (request.alarmId > 0) AlarmScheduler.cancelSnooze(this, request.alarmId)
                }
            }
        } catch (error: SecurityException) {
            Log.e(AlarmContract.TAG, "Could not update the schedule after $event", error)
        }
        AlarmEvents.publish(this, event, request.alarmId, snoozeMinutes, request.label)
        if (foreground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        stopSelf()
    }

    private fun promote(notification: Notification) {
        ensureChannel()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                AlarmContract.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(AlarmContract.NOTIFICATION_ID, notification)
        }
        foreground = true
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(AlarmContract.CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            AlarmContract.CHANNEL_ID,
            "Alarms",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Shown while a Twince alarm is ringing"
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(request: RingRequest): Notification {
        val fullScreen = activityPending(request, request.alarmId + 30_000)
        val content = activityPending(request, request.alarmId + 40_000)
        val dismiss = servicePending(ACTION_DISMISS, request, request.alarmId + 50_000, 0)
        val snooze = servicePending(ACTION_SNOOZE, request, request.alarmId + 60_000, 5)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, AlarmContract.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(request.label)
            .setContentText("Alarm is ringing")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setColor(Color.parseColor("#3DDCFF"))
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(content)
            .addAction(action(R.drawable.ic_close, "Dismiss", dismiss))
            .addAction(action(R.drawable.ic_stat_alarm, "Snooze 5min", snooze))
            .build()
    }

    private fun action(icon: Int, title: String, pending: PendingIntent): Notification.Action {
        return Notification.Action.Builder(Icon.createWithResource(this, icon), title, pending).build()
    }

    private fun activityPending(request: RingRequest, requestCode: Int): PendingIntent {
        val intent = request.fillIntent(Intent(this, AlarmRingActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            data = Uri.parse("twince://ring/${request.alarmId}/$requestCode")
        }
        return PendingIntent.getActivity(this, requestCode, intent, AlarmContract.PI_FLAGS)
    }

    private fun servicePending(
        action: String,
        request: RingRequest,
        requestCode: Int,
        minutes: Int,
    ): PendingIntent {
        val intent = request.serviceIntent(this, action, minutes).apply {
            data = Uri.parse("twince://ring-action/${request.alarmId}/$action/$minutes")
        }
        return PendingIntent.getService(this, requestCode, intent, AlarmContract.PI_FLAGS)
    }

    private fun launchActivity(request: RingRequest) {
        val intent = request.fillIntent(Intent(this, AlarmRingActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        try {
            startActivity(intent)
        } catch (error: Exception) {
            Log.w(AlarmContract.TAG, "Direct activity start blocked; full-screen intent remains", error)
        }
    }

    @Suppress("DEPRECATION")
    private fun holdWakes() {
        val power = getSystemService(PowerManager::class.java)
        if (partialWake?.isHeld != true) {
            partialWake = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "twince:alarm-cpu").apply {
                setReferenceCounted(false)
                acquire(RING_TIMEOUT_MS)
            }
        }
        if (screenWake?.isHeld != true) {
            screenWake = power.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "twince:alarm-screen",
            ).apply {
                setReferenceCounted(false)
                acquire(15_000L)
            }
        }
    }

    private fun releaseWakes() {
        partialWake?.let { if (it.isHeld) it.release() }
        screenWake?.let { if (it.isHeld) it.release() }
        partialWake = null
        screenWake = null
    }

    companion object {
        const val ACTION_START = "com.twince.alarm.action.START_RING"
        const val ACTION_DISMISS = "com.twince.alarm.action.DISMISS"
        const val ACTION_SNOOZE = "com.twince.alarm.action.SNOOZE"
        const val ACTION_RESTART = "com.twince.alarm.action.RESTART"
        private const val RING_TIMEOUT_MS = 10 * 60 * 1000L

        fun start(context: Context, request: RingRequest) {
            val intent = request.serviceIntent(context, ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun actionToEvent(action: String): String {
            return when (action) {
                ACTION_SNOOZE -> AlarmContract.EVENT_SNOOZE
                ACTION_RESTART -> AlarmContract.EVENT_RESTART
                else -> AlarmContract.EVENT_DISMISS
            }
        }
    }
}
