package com.twince.alarm

import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

data class TwinceAlarm(
    val id: Int,
    val hour: Int,
    val minute: Int,
    val label: String,
    val subtitle: String,
    val enabled: Boolean,
    val vibrate: Boolean,
    val soundUri: String,
    val repeatDays: List<Int>,
    val weekTags: List<String> = emptyList(),
)

data class SnoozeRecord(
    val alarmId: Int,
    val triggerAt: Long,
)

/**
 * Single persistence point shared by Flutter and the native alarm process.
 * Alarms survive process death so [BootReceiver] can reschedule them.
 */
object AlarmStore {
    private const val PREFS = "twince_alarm_store"
    private const val KEY_ALARMS = "alarms"
    private const val KEY_NEXT_ID = "next_id"
    private const val KEY_EVENTS = "events"
    private const val KEY_SNOOZES = "snoozes"
    private const val KEY_CALLBACK_PACKAGE = "callback_package"
    private const val KEY_CALLBACK_CLASS = "callback_class"
    private const val KEY_PLAN_LIBRARY = "plan_library"

    private val lock = Any()

    private fun prefs(context: Context): SharedPreferences {
        return context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    fun getAlarms(context: Context): List<TwinceAlarm> = synchronized(lock) {
        readAlarms(prefs(context))
    }

    fun find(context: Context, id: Int): TwinceAlarm? {
        return getAlarms(context).firstOrNull { it.id == id }
    }

    fun upsert(context: Context, alarm: TwinceAlarm): TwinceAlarm = synchronized(lock) {
        val store = prefs(context)
        val current = readAlarms(store).toMutableList()
        var nextId = store.getInt(KEY_NEXT_ID, 1).coerceAtLeast(1)
        val id = if (alarm.id > 0) alarm.id else nextId++
        if (id >= nextId) nextId = id + 1
        val saved = alarm.copy(
            id = id,
            hour = alarm.hour.coerceIn(0, 23),
            minute = alarm.minute.coerceIn(0, 59),
            label = alarm.label.ifBlank { "Alarm" },
            subtitle = alarm.subtitle.ifBlank { AlarmContract.DEFAULT_SUBTITLE },
            repeatDays = sanitizeRepeatDays(alarm.repeatDays),
            weekTags = sanitizeWeekTags(alarm.weekTags),
        )
        val index = current.indexOfFirst { it.id == saved.id }
        if (index >= 0) current[index] = saved else current.add(saved)
        store.edit()
            .putString(KEY_ALARMS, writeAlarms(current))
            .putInt(KEY_NEXT_ID, nextId)
            .commit()
        saved
    }

    fun delete(context: Context, id: Int) = synchronized(lock) {
        val store = prefs(context)
        val current = readAlarms(store).filterNot { it.id == id }
        val snoozes = readSnoozes(store).filterNot { it.alarmId == id }
        store.edit()
            .putString(KEY_ALARMS, writeAlarms(current))
            .putString(KEY_SNOOZES, writeSnoozes(snoozes))
            .commit()
    }

    fun setEnabled(context: Context, id: Int, enabled: Boolean): TwinceAlarm? {
        val existing = find(context, id) ?: return null
        return upsert(context, existing.copy(enabled = enabled))
    }

    fun setSnooze(context: Context, alarmId: Int, triggerAt: Long) = synchronized(lock) {
        val store = prefs(context)
        val snoozes = readSnoozes(store).filterNot { it.alarmId == alarmId }.toMutableList()
        snoozes.add(SnoozeRecord(alarmId, triggerAt))
        store.edit().putString(KEY_SNOOZES, writeSnoozes(snoozes)).commit()
    }

    fun clearSnooze(context: Context, alarmId: Int) = synchronized(lock) {
        val store = prefs(context)
        val snoozes = readSnoozes(store).filterNot { it.alarmId == alarmId }
        store.edit().putString(KEY_SNOOZES, writeSnoozes(snoozes)).commit()
    }

    fun getSnoozes(context: Context): List<SnoozeRecord> = synchronized(lock) {
        readSnoozes(prefs(context))
    }

    fun snoozeUntil(context: Context, alarmId: Int): Long {
        val now = System.currentTimeMillis()
        return getSnoozes(context).firstOrNull { it.alarmId == alarmId && it.triggerAt > now }?.triggerAt ?: 0L
    }

    fun setCallbackComponent(context: Context, packageName: String?, className: String?) {
        prefs(context).edit()
            .putString(KEY_CALLBACK_PACKAGE, packageName.orEmpty())
            .putString(KEY_CALLBACK_CLASS, className.orEmpty())
            .commit()
    }

    fun callbackComponent(context: Context): ComponentName? {
        val store = prefs(context)
        val pkg = store.getString(KEY_CALLBACK_PACKAGE, null)?.takeIf { it.isNotBlank() } ?: return null
        val cls = store.getString(KEY_CALLBACK_CLASS, null)?.takeIf { it.isNotBlank() } ?: return null
        return ComponentName(pkg, cls)
    }

    fun appendEvent(context: Context, payload: Map<String, Any?>) = synchronized(lock) {
        val store = prefs(context)
        val array = JSONArray(store.getString(KEY_EVENTS, "[]"))
        array.put(JSONObject(payload))
        while (array.length() > 50) {
            array.remove(0)
        }
        store.edit().putString(KEY_EVENTS, array.toString()).commit()
    }

    fun consumeEvents(context: Context): List<Map<String, Any?>> = synchronized(lock) {
        val store = prefs(context)
        val array = JSONArray(store.getString(KEY_EVENTS, "[]"))
        val events = buildList {
            for (i in 0 until array.length()) {
                add(array.getJSONObject(i).toPrimitiveMap())
            }
        }
        store.edit().putString(KEY_EVENTS, "[]").commit()
        events
    }

    fun toMap(context: Context, alarm: TwinceAlarm): HashMap<String, Any?> {
        return hashMapOf(
            "id" to alarm.id,
            "hour" to alarm.hour,
            "minute" to alarm.minute,
            "label" to alarm.label,
            "subtitle" to alarm.subtitle,
            "enabled" to alarm.enabled,
            "vibrate" to alarm.vibrate,
            "soundUri" to alarm.soundUri,
            "repeatDays" to ArrayList(alarm.repeatDays),
            "weekTags" to ArrayList(alarm.weekTags),
            "snoozeUntil" to snoozeUntil(context, alarm.id),
        )
    }

    fun toJson(alarm: TwinceAlarm): JSONObject {
        return JSONObject()
            .put("id", alarm.id)
            .put("hour", alarm.hour)
            .put("minute", alarm.minute)
            .put("label", alarm.label)
            .put("subtitle", alarm.subtitle)
            .put("enabled", alarm.enabled)
            .put("vibrate", alarm.vibrate)
            .put("soundUri", alarm.soundUri)
            .put("repeatDays", JSONArray(alarm.repeatDays))
            .put("weekTags", JSONArray(alarm.weekTags))
    }

    fun fromArgs(args: Map<*, *>): TwinceAlarm {
        val hour = args[AlarmContract.EXTRA_HOUR].asInt(-1)
        val minute = args[AlarmContract.EXTRA_MINUTE].asInt(-1)
        require(hour in 0..23) { "hour must be 0..23" }
        require(minute in 0..59) { "minute must be 0..59" }
        return TwinceAlarm(
            id = args[AlarmContract.EXTRA_ALARM_ID].asInt(args["id"].asInt(0)),
            hour = hour,
            minute = minute,
            label = args[AlarmContract.EXTRA_LABEL].asString("Alarm"),
            subtitle = args[AlarmContract.EXTRA_SUBTITLE].asString(AlarmContract.DEFAULT_SUBTITLE),
            enabled = args[AlarmContract.EXTRA_ENABLED].asBool(true),
            vibrate = args[AlarmContract.EXTRA_VIBRATE].asBool(true),
            soundUri = args[AlarmContract.EXTRA_SOUND_URI].asString(""),
            repeatDays = readDaysArg(args[AlarmContract.EXTRA_REPEAT_DAYS]),
            weekTags = readWeekTags(args["weekTags"]),
        )
    }

    private fun readAlarms(store: SharedPreferences): List<TwinceAlarm> {
        val raw = store.getString(KEY_ALARMS, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    add(fromJson(array.getJSONObject(i)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun fromJson(obj: JSONObject): TwinceAlarm {
        val days = obj.optJSONArray("repeatDays")
        val repeat = buildList {
            if (days != null) {
                for (i in 0 until days.length()) add(days.optInt(i))
            }
        }
        return TwinceAlarm(
            id = obj.optInt("id"),
            hour = obj.optInt("hour").coerceIn(0, 23),
            minute = obj.optInt("minute").coerceIn(0, 59),
            label = obj.optString("label", "Alarm"),
            subtitle = obj.optString("subtitle", AlarmContract.DEFAULT_SUBTITLE),
            enabled = obj.optBoolean("enabled", true),
            vibrate = obj.optBoolean("vibrate", true),
            soundUri = obj.optString("soundUri", ""),
            repeatDays = sanitizeRepeatDays(repeat),
            weekTags = readWeekTags(obj.optJSONArray("weekTags")),
        )
    }

    private fun writeAlarms(alarms: List<TwinceAlarm>): String {
        val array = JSONArray()
        alarms.forEach { array.put(toJson(it)) }
        return array.toString()
    }

    private fun readSnoozes(store: SharedPreferences): List<SnoozeRecord> {
        val raw = store.getString(KEY_SNOOZES, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            buildList {
                for (i in 0 until array.length()) {
                    val obj = array.getJSONObject(i)
                    add(SnoozeRecord(obj.optInt("alarmId"), obj.optLong("triggerAt")))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun writeSnoozes(snoozes: List<SnoozeRecord>): String {
        val array = JSONArray()
        snoozes.forEach {
            array.put(JSONObject().put("alarmId", it.alarmId).put("triggerAt", it.triggerAt))
        }
        return array.toString()
    }

    fun loadPlanLibrary(context: Context): String = synchronized(lock) {
        prefs(context).getString(KEY_PLAN_LIBRARY, "") ?: ""
    }

    fun savePlanLibrary(context: Context, json: String) = synchronized(lock) {
        prefs(context).edit().putString(KEY_PLAN_LIBRARY, json).commit()
    }

    private fun readDaysArg(raw: Any?): List<Int> {
        val values = when (raw) {
            is List<*> -> raw.mapNotNull { it.asIntOrNull() }
            is IntArray -> raw.toList()
            else -> emptyList()
        }
        return sanitizeRepeatDays(values)
    }

    private fun readWeekTags(raw: Any?): List<String> {
        val values = when (raw) {
            is List<*> -> raw.mapNotNull { it?.toString() }
            is JSONArray -> buildList {
                for (i in 0 until raw.length()) add(raw.optString(i))
            }
            else -> emptyList()
        }
        return sanitizeWeekTags(values)
    }

    private fun sanitizeWeekTags(tags: List<String>): List<String> {
        val normalized = tags.map { it.trim().uppercase() }.filter { it == "Z" || it == "F" }.toSet()
        return buildList {
            if ("Z" in normalized) add("Z")
            if ("F" in normalized) add("F")
        }
    }
}

internal fun JSONObject.toPrimitiveMap(): HashMap<String, Any?> {
    val map = HashMap<String, Any?>()
    val keys = keys()
    while (keys.hasNext()) {
        val key = keys.next()
        map[key] = when (val value = opt(key)) {
            JSONObject.NULL -> null
            is Int -> value
            is Long -> value
            is Double -> value
            is Boolean -> value
            is String -> value
            else -> value?.toString()
        }
    }
    return map
}

internal fun Any?.asInt(default: Int): Int = asIntOrNull() ?: default

internal fun Any?.asIntOrNull(): Int? = when (this) {
    is Int -> this
    is Long -> toInt()
    is Double -> toInt()
    is Float -> toInt()
    is Number -> toInt()
    is String -> toIntOrNull()
    else -> null
}

internal fun Any?.asBool(default: Boolean): Boolean = this as? Boolean ?: default

internal fun Any?.asString(default: String): String = (this as? String)?.trim()?.ifEmpty { default } ?: default
