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
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pendingPermission: MethodChannel.Result? = null
    private var clockIntentConsumed = false
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingBackupContent: String? = null
    private var selectedBackupUri: Uri? = null
    private var selectedBackupFlags = 0
    private val backupPrefs get() = getSharedPreferences("backup_document", MODE_PRIVATE)

    private fun documentName(uri: Uri): String {
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: error("Could not determine the document filename")
    }

    private fun backupNameValid(name: String) = name.startsWith("TWINCEALARM_") && name.endsWith(".json") &&
        name.length > "TWINCEALARM_.json".length && !name.contains('/') && !name.contains('\\')

    private fun currentUri(): Uri? = backupPrefs.getString("uri", null)?.let(Uri::parse)
    private fun currentInfo(): Map<String, Any>? {
        val uri = currentUri() ?: return null
        val name = try { documentName(uri) } catch (_: Exception) { backupPrefs.getString("name", "Unknown file") ?: "Unknown file" }
        return mapOf("name" to name)
    }
    private fun rememberDocument(uri: Uri, flags: Int) {
        val granted = flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try { contentResolver.takePersistableUriPermission(uri, granted) } catch (_: SecurityException) { }
        val name = documentName(uri)
        check(backupPrefs.edit().putString("uri", uri.toString()).putString("name", name).commit()) { "Could not remember the selected backup" }
    }
    private fun writeDocument(uri: Uri, content: String) {
        val output = contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open the selected destination")
        output.use { it.write(content.toByteArray(Charsets.UTF_8)) }
    }


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
        // Register platform plugins (e.g. package_info_plus) so that
        // PackageInfo.fromPlatform() can resolve the app version.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.twince.alarm/backup").setMethodCallHandler { call, result ->
            try { handleBackup(call, result) } catch (error: Exception) {
                result.error("backup_error", error.message ?: "Backup operation failed", null)
            }
        }
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
                AlarmSounds.preview(
                    this,
                    call.argument<String>("uri").orEmpty(),
                    call.argument<Boolean>("loop") == true,
                )
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
            "loadPlanLibrary" -> result.success(AlarmStore.loadPlanLibrary(this))
            "savePlanLibrary" -> {
                AlarmStore.savePlanLibrary(this, call.argument<String>("json").orEmpty())
                result.success(true)
            }
            "loadLastAlarmSound" -> result.success(AlarmStore.loadLastAlarmSound(this))
            "saveLastAlarmSound" -> {
                AlarmStore.saveLastAlarmSound(this, call.argument<String>("uri").orEmpty())
                result.success(true)
            }
            "loadFavoriteAlarmSounds" -> result.success(AlarmStore.loadFavoriteAlarmSounds(this))
            "saveFavoriteAlarmSounds" -> {
                val uris = call.argument<List<*>>("uris").orEmpty().map { it?.toString().orEmpty() }
                AlarmStore.saveFavoriteAlarmSounds(this, uris)
                result.success(true)
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
                result.success(request.token)
            }
            "consumeClockIntent" -> result.success(consumeClockIntent())
            else -> result.notImplemented()
        }
    }

    private fun handleBackup(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "save", "choose" -> {
                if (pendingBackupResult != null) { result.error("busy", "A document picker is already open.", null); return }
                val saving = call.method == "save"
                val picker = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    if (saving) putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                }
                pendingBackupContent = if (saving) call.argument<String>("content") else null
                pendingBackupResult = result
                try { @Suppress("DEPRECATION") startActivityForResult(picker, if (saving) 7201 else 7202) }
                catch (error: Exception) { pendingBackupResult = null; pendingBackupContent = null; throw error }
            }
            "current" -> result.success(currentInfo())
            "useSelected" -> {
                val uri = selectedBackupUri ?: error("The imported document is no longer selected")
                rememberDocument(uri, selectedBackupFlags)
                selectedBackupUri = null
                result.success(currentInfo())
            }
            "saveCurrent" -> {
                val uri = currentUri() ?: error("No current backup")
                val content = call.argument<String>("content") ?: error("Missing backup content")
                val writable = contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
                if (!writable || !backupNameValid(documentName(uri))) {
                    result.success(false)
                } else {
                    writeDocument(uri, content)
                    result.success(true)
                }
            }
            "rename" -> {
                val uri = currentUri() ?: error("No current backup")
                val name = call.argument<String>("name") ?: error("Missing filename")
                require(backupNameValid(name)) { "Filename must start with TWINCEALARM_ and end in .json" }
                val flags = try {
                    contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use {
                        if (it.moveToFirst()) it.getInt(0) else 0
                    } ?: 0
                } catch (_: Exception) { 0 }
                val writable = contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
                if (!writable || flags and DocumentsContract.Document.FLAG_SUPPORTS_RENAME == 0) {
                    result.success(false)
                } else {
                    val renamed = DocumentsContract.renameDocument(contentResolver, uri, name) ?: error("The document provider could not rename this file")
                    rememberDocument(renamed, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    result.success(true)
                }
            }
            "restore" -> {
                val args = call.arguments as? Map<*, *> ?: error("Missing backup data")
                val rawAlarms = args["alarms"] as? List<*> ?: error("Missing alarms")
                val alarms = rawAlarms.map { AlarmStore.fromArgs(it as? Map<*, *> ?: error("Invalid alarm")) }
                require(alarms.all { it.id > 0 } && alarms.map { it.id }.distinct().size == alarms.size) { "Invalid alarm IDs" }
                val plans = args["planLibrary"] as? String ?: error("Missing plans")
                val last = args["lastSound"] as? String ?: error("Missing sound")
                val favorites = (args["favoriteSounds"] as? List<*>)?.map { it as? String ?: error("Invalid sound") } ?: error("Missing favorites")
                AlarmStore.replaceBackup(this, alarms, plans, last, favorites)
                var scheduled = true
                try { AlarmScheduler.rescheduleAll(this) } catch (error: Exception) {
                    Log.e(AlarmContract.TAG, "Restore saved but rescheduling failed", error)
                    scheduled = false
                }
                val permissions = permissionStatus()
                result.success(hashMapOf("exactAlarm" to (permissions["exactAlarm"] == true && scheduled), "notifications" to (permissions["notifications"] == true), "fullScreenIntent" to (permissions["fullScreenIntent"] == true)))
            }
            else -> result.notImplemented()
        }
    }

    @Deprecated("Android document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7201 && requestCode != 7202) return
        val result = pendingBackupResult ?: return
        val content = pendingBackupContent
        pendingBackupResult = null
        pendingBackupContent = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result.success(if (requestCode == 7201) false else null)
            return
        }
        try {
            val uri = data.data!!
            if (requestCode == 7201) {
                val name = documentName(uri)
                require(backupNameValid(name)) { "Choose a filename starting with TWINCEALARM_ and ending in .json" }
                writeDocument(uri, content ?: error("Missing backup"))
                rememberDocument(uri, data.flags)
                result.success(true)
            } else {
                val input = contentResolver.openInputStream(uri) ?: error("Cannot open the selected file")
                val bytes = input.use { stream ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= 10 * 1024 * 1024) { "Backup exceeds the 10 MB limit" }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                val decoder = Charsets.UTF_8.newDecoder()
                val decoded = decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                selectedBackupUri = uri
                selectedBackupFlags = data.flags
                result.success(decoded)
            }
        } catch (error: Exception) {
            result.error("backup_file", error.message ?: "Could not access the selected file", null)
        }
    }

    private fun payload(saved: SaveResult): HashMap<String, Any?> {
        val map = AlarmStore.toMap(this, saved.alarm)
        map["scheduled"] = saved.scheduleError.isEmpty()
        map["scheduleError"] = saved.scheduleError
        return map
    }

    private fun permissionStatus(): HashMap<String, Boolean> {
        val notificationPermission = if (Build.VERSION.SDK_INT >= 33) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val notifications = notificationPermission &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || getSystemService(NotificationManager::class.java).areNotificationsEnabled())
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
