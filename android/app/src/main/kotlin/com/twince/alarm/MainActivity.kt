package com.twince.alarm

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.AlarmClock
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result? = null
    private var clockIntentConsumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            AlarmScheduler.rescheduleAll(this)
        } catch (error: Exception) {
            Log.e(AlarmContract.TAG, "Initial reschedule failed", error)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        clockIntentConsumed = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (error: Exception) {
                Log.e(AlarmContract.TAG, "Method ${call.method} failed", error)
                result.error("native_error", error.message, null)
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                AlarmEvents.sink = events
            }

            override fun onCancel(arguments: Any?) {
                AlarmEvents.sink = null
            }
        })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAlarms" -> result.success(AlarmStore.getAlarms(this).map { AlarmStore.toMap(this, it) })
            "upsertAlarm" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("invalid_alarm", "Missing alarm", null)
                    return
                }
                val saved = AlarmRepository.saveAndSchedule(this, AlarmStore.fromArgs(args))
                result.success(payload(saved))
            }
            "deleteAlarm" -> {
                val id = call.argument<Int>("id") ?: call.argument<Int>("alarmId")
                if (id == null || id <= 0) {
                    result.error("invalid_alarm", "id is required", null)
                    return
                }
                AlarmRepository.delete(this, id)
                result.success(true)
            }
            "setEnabled" -> {
                val id = call.argument<Int>("id") ?: call.argument<Int>("alarmId")
                val enabled = call.argument<Boolean>("enabled")
                if (id == null || enabled == null) {
                    result.error("invalid_alarm", "id and enabled are required", null)
                    return
                }
                val saved = AlarmRepository.setEnabled(this, id, enabled)
                if (saved == null) {
                    result.error("not_found", "Alarm $id was not found", null)
                } else {
                    result.success(payload(saved))
                }
            }
            "listAlarmSounds" -> {
                io.execute {
                    try {
                        val sounds = AlarmSounds.list(this)
                        runOnUiThread { result.success(sounds) }
                    } catch (error: Exception) {
                        Log.e(AlarmContract.TAG, "Unable to list alarm tones", error)
                        runOnUiThread { result.error("sound_list", error.message, null) }
                    }
                }
            }
            "previewSound" -> {
                AlarmSounds.preview(this, call.argument<String>("uri").orEmpty())
                result.success(true)
            }
            "stopPreview" -> {
                AlarmSounds.stop()
                result.success(true)
            }
            "permissions" -> result.success(permissionStatus())
            "requestNotifications" -> requestNotifications(result)
            "openExactAlarmSettings" -> {
                openExactAlarmSettings()
                result.success(true)
            }
            "openFullScreenIntentSettings" -> {
                openFullScreenSettings()
                result.success(true)
            }
            "consumeEvents" -> result.success(AlarmStore.consumeEvents(this))
            "rescheduleAll" -> {
                AlarmScheduler.rescheduleAll(this)
                result.success(AlarmScheduler.canScheduleExact(this))
            }
            "previewRing" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val request = RingRequest(
                    alarmId = args[AlarmContract.EXTRA_ALARM_ID].asInt(0),
                    hour = args[AlarmContract.EXTRA_HOUR].asInt(7).coerceIn(0, 23),
                    minute = args[AlarmContract.EXTRA_MINUTE].asInt(30).coerceIn(0, 59),
                    label = args[AlarmContract.EXTRA_LABEL].asString("Morning workout"),
                    subtitle = args[AlarmContract.EXTRA_SUBTITLE].asString(AlarmContract.DEFAULT_SUBTITLE),
                    vibrate = args[AlarmContract.EXTRA_VIBRATE].asBool(true),
                    soundUri = args[AlarmContract.EXTRA_SOUND_URI].asString(""),
                    preview = true,
                    token = System.currentTimeMillis(),
                )
                AlarmRingService.start(this, request)
                result.success(true)
            }
            "consumeClockIntent" -> result.success(consumeClockIntent())
            else -> result.notImplemented()
        }
    }

    private fun payload(saved: SaveResult): HashMap<String, Any?> {
        val map = AlarmStore.toMap(this, saved.alarm)
        map["scheduled"] = saved.scheduleError.isEmpty()
        map["scheduleError"] = saved.scheduleError
        return map
    }

    private fun permissionStatus(): HashMap<String, Boolean> {
        val notifications = if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val fullScreen = if (Build.VERSION.SDK_INT >= 34) {
            getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
        } else {
            true
        }
        return hashMapOf(
            "notifications" to notifications,
            "exactAlarm" to AlarmScheduler.canScheduleExact(this),
            "fullScreenIntent" to fullScreen,
        )
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        startActivity(
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

    private fun openFullScreenSettings() {
        if (Build.VERSION.SDK_INT < 34) return
        startActivity(
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
            },
        )
    }

    private fun consumeClockIntent(): HashMap<String, Any?>? {
        val current = intent ?: return null
        val action = current.action ?: return null
        if (action != AlarmClock.ACTION_SET_ALARM && action != AlarmClock.ACTION_SHOW_ALARMS) return null
        if (clockIntentConsumed) return null
        clockIntentConsumed = true
        val days = current.getIntegerArrayListExtra(AlarmClock.EXTRA_DAYS)
            ?.map { calendarDayToIso(it) }
            ?: emptyList()
        return hashMapOf(
            "action" to action,
            "hour" to current.getIntExtra(AlarmClock.EXTRA_HOUR, -1),
            "minute" to current.getIntExtra(AlarmClock.EXTRA_MINUTES, -1),
            "label" to current.getStringExtra(AlarmClock.EXTRA_MESSAGE).orEmpty(),
            "skipUi" to current.getBooleanExtra(AlarmClock.EXTRA_SKIP_UI, false),
            "vibrate" to current.getBooleanExtra(AlarmClock.EXTRA_VIBRATE, true),
            "soundUri" to current.getStringExtra(AlarmClock.EXTRA_RINGTONE).orEmpty(),
            "repeatDays" to ArrayList(days),
        )
    }

    companion object {
        private const val METHOD_CHANNEL = "com.twince.alarm/alarms"
        private const val EVENT_CHANNEL = "com.twince.alarm/events"
        private const val REQUEST_NOTIFICATIONS = 4102
    }
}
