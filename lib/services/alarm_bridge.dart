import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';

/// Talks to the Android alarm engine on `com.twince.alarm/alarms`.
///
/// Live outcomes arrive on [events]:
/// - `dismiss` — onDismiss(alarmId)
/// - `snooze` — onSnooze(alarmId, durationMinutes)
/// - `restart` — onRestart(alarmId)
///
/// Other apps send explicit broadcasts to package `com.twince.alarm`:
/// `com.twince.alarm.ACTION_CREATE_ALARM` and
/// `com.twince.alarm.ACTION_CANCEL_ALARM`.
/// They must declare `com.twince.alarm.permission.CONTROL_ALARMS`.
class AlarmBridge {
  AlarmBridge._();

  static final instance = AlarmBridge._();

  static const _methods = MethodChannel('com.twince.alarm/alarms');
  static const _events = EventChannel('com.twince.alarm/events');

  Stream<AlarmEvent> get events {
    return _events.receiveBroadcastStream().map((raw) {
      return AlarmEvent.fromMap(Map<dynamic, dynamic>.from(raw as Map));
    });
  }

  Future<List<AlarmItem>> getAlarms() async {
    final raw = await _methods.invokeMethod<dynamic>('getAlarms');
    return _maps(raw).map(AlarmItem.fromMap).toList();
  }

  Future<AlarmItem> upsert(AlarmItem alarm) async {
    final raw = await _methods.invokeMethod<dynamic>('upsertAlarm', alarm.toMap());
    return AlarmItem.fromMap(_map(raw));
  }

  Future<void> delete(int id) {
    return _methods.invokeMethod<dynamic>('deleteAlarm', {'id': id});
  }

  Future<AlarmItem> setEnabled(int id, bool enabled) async {
    final raw = await _methods.invokeMethod<dynamic>('setEnabled', {
      'id': id,
      'enabled': enabled,
    });
    return AlarmItem.fromMap(_map(raw));
  }

  Future<List<AlarmSound>> listSounds() async {
    final raw = await _methods.invokeMethod<dynamic>('listAlarmSounds');
    return _maps(raw).map(AlarmSound.fromMap).toList();
  }

  Future<void> previewSound(String uri) {
    return _methods.invokeMethod<dynamic>('previewSound', {'uri': uri});
  }

  Future<void> stopPreview() {
    return _methods.invokeMethod<dynamic>('stopPreview');
  }

  Future<AlarmPermissions> permissions() async {
    final raw = await _methods.invokeMethod<dynamic>('permissions');
    return AlarmPermissions.fromMap(_map(raw));
  }

  Future<bool> requestNotifications() async {
    final granted = await _methods.invokeMethod<dynamic>('requestNotifications');
    return granted == true;
  }

  Future<void> openExactAlarmSettings() {
    return _methods.invokeMethod<dynamic>('openExactAlarmSettings');
  }

  Future<void> openFullScreenIntentSettings() {
    return _methods.invokeMethod<dynamic>('openFullScreenIntentSettings');
  }

  Future<List<AlarmEvent>> consumeEvents() async {
    final raw = await _methods.invokeMethod<dynamic>('consumeEvents');
    return _maps(raw).map(AlarmEvent.fromMap).toList();
  }

  Future<void> rescheduleAll() {
    return _methods.invokeMethod<dynamic>('rescheduleAll');
  }

  Future<void> previewRing({
    int id = 0,
    int hour = 7,
    int minute = 30,
    String label = 'Morning workout',
    String subtitle = 'Time to start your task',
    bool vibrate = true,
    String soundUri = '',
  }) {
    return _methods.invokeMethod<dynamic>('previewRing', {
      'alarmId': id,
      'hour': hour,
      'minute': minute,
      'label': label,
      'subtitle': subtitle,
      'vibrate': vibrate,
      'soundUri': soundUri,
    });
  }

  Future<ClockLaunch?> consumeClockIntent() async {
    final raw = await _methods.invokeMethod<dynamic>('consumeClockIntent');
    if (raw == null) return null;
    return ClockLaunch.fromMap(_map(raw));
  }
}

Map<dynamic, dynamic> _map(Object? raw) {
  if (raw is Map) return Map<dynamic, dynamic>.from(raw);
  return const {};
}

List<Map<dynamic, dynamic>> _maps(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((item) => Map<dynamic, dynamic>.from(item)).toList();
}
