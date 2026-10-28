import 'package:flutter/foundation.dart';
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
///
/// Flutter Web has no Android engine. [instance] then stores alarms in
/// [_WebAlarmMemory] for the current page only, so the form can be saved and
/// the list can show them. That memory does not ring, notify, schedule, or
/// survive a browser restart.
class AlarmBridge {
  AlarmBridge._() : _web = kIsWeb ? _WebAlarmMemory() : null;

  static final instance = AlarmBridge._();

  /// In-memory bridge for tests. Production Android keeps using the channel.
  @visibleForTesting
  factory AlarmBridge.memory() => AlarmBridge._memory(_WebAlarmMemory());

  AlarmBridge._memory(this._web);

  static const _methods = MethodChannel('com.twince.alarm/alarms');
  static const _events = EventChannel('com.twince.alarm/events');
  static const _webSounds = [AlarmSound(name: 'Default alarm', uri: '')];

  final _WebAlarmMemory? _web;
  _WebAlarmMemory? _testMemory;

  _WebAlarmMemory? get _memory => _testMemory ?? _web;

  /// Points [instance] at a fresh in-memory session. VM tests use this
  /// because [kIsWeb] is false there. Android builds leave it unset.
  @visibleForTesting
  void useMemorySession() {
    _testMemory = _WebAlarmMemory();
  }

  @visibleForTesting
  void clearMemorySession() {
    _testMemory = null;
  }

  Stream<AlarmEvent> get events {
    if (_memory != null) return const Stream<AlarmEvent>.empty();
    return _events.receiveBroadcastStream().map((raw) {
      return AlarmEvent.fromMap(Map<dynamic, dynamic>.from(raw as Map));
    });
  }

  Future<List<AlarmItem>> getAlarms() async {
    final memory = _memory;
    if (memory != null) return memory.getAlarms();
    final raw = await _methods.invokeMethod<dynamic>('getAlarms');
    return _maps(raw).map(AlarmItem.fromMap).toList();
  }

  Future<AlarmItem> upsert(AlarmItem alarm) async {
    final memory = _memory;
    if (memory != null) return memory.upsert(alarm);
    final raw = await _methods.invokeMethod<dynamic>(
      'upsertAlarm',
      alarm.toMap(),
    );
    return AlarmItem.fromMap(_map(raw));
  }

  Future<void> delete(int id) {
    final memory = _memory;
    if (memory != null) {
      memory.delete(id);
      return Future<void>.value();
    }
    return _methods.invokeMethod<dynamic>('deleteAlarm', {'id': id});
  }

  Future<AlarmItem> setEnabled(int id, bool enabled) async {
    final memory = _memory;
    if (memory != null) return memory.setEnabled(id, enabled);
    final raw = await _methods.invokeMethod<dynamic>('setEnabled', {
      'id': id,
      'enabled': enabled,
    });
    return AlarmItem.fromMap(_map(raw));
  }

  Future<List<AlarmSound>> listSounds() async {
    if (_memory != null) return _webSounds;
    final raw = await _methods.invokeMethod<dynamic>('listAlarmSounds');
    return _maps(raw).map(AlarmSound.fromMap).toList();
  }

  Future<void> previewSound(String uri, {bool loop = false}) {
    if (_memory != null) return Future<void>.value();
    return _methods.invokeMethod<dynamic>('previewSound', {
      'uri': uri,
      'loop': loop,
    });
  }

  Future<void> stopPreview() {
    if (_memory != null) return Future<void>.value();
    return _methods.invokeMethod<dynamic>('stopPreview');
  }

  Future<AlarmPermissions> permissions() async {
    if (_memory != null) return AlarmPermissions.granted;
    final raw = await _methods.invokeMethod<dynamic>('permissions');
    return AlarmPermissions.fromMap(_map(raw));
  }

  Future<bool> requestNotifications() async {
    if (_memory != null) return true;
    final granted = await _methods.invokeMethod<dynamic>(
      'requestNotifications',
    );
    return granted == true;
  }

  Future<void> openExactAlarmSettings() {
    if (_memory != null) return Future<void>.value();
    return _methods.invokeMethod<dynamic>('openExactAlarmSettings');
  }

  Future<void> openFullScreenIntentSettings() {
    if (_memory != null) return Future<void>.value();
    return _methods.invokeMethod<dynamic>('openFullScreenIntentSettings');
  }

  Future<List<AlarmEvent>> consumeEvents() async {
    if (_memory != null) return const [];
    final raw = await _methods.invokeMethod<dynamic>('consumeEvents');
    return _maps(raw).map(AlarmEvent.fromMap).toList();
  }

  Future<void> rescheduleAll() {
    if (_memory != null) return Future<void>.value();
    return _methods.invokeMethod<dynamic>('rescheduleAll');
  }

  Future<String> loadPlanLibrary() async {
    if (_memory != null) return _memory!.planLibrary;
    final raw = await _methods.invokeMethod<dynamic>('loadPlanLibrary');
    return raw as String? ?? '';
  }

  Future<void> savePlanLibrary(String json) {
    final memory = _memory;
    if (memory != null) {
      memory.planLibrary = json;
      return Future<void>.value();
    }
    return _methods.invokeMethod<dynamic>('savePlanLibrary', {'json': json});
  }

  /// URI of the sound last chosen in the alarm editor. Empty is the default tone.
  Future<String> loadLastAlarmSound() async {
    final memory = _memory;
    if (memory != null) return memory.lastAlarmSound;
    try {
      final raw = await _methods.invokeMethod<dynamic>('loadLastAlarmSound');
      return raw as String? ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<void> saveLastAlarmSound(String uri) async {
    final memory = _memory;
    if (memory != null) {
      memory.lastAlarmSound = uri;
      return;
    }
    try {
      await _methods.invokeMethod<dynamic>('saveLastAlarmSound', {'uri': uri});
    } on PlatformException {
      // A missing preference store must not block choosing a sound.
    }
  }

  Future<List<String>> loadFavoriteAlarmSounds() async {
    final memory = _memory;
    if (memory != null) return List<String>.of(memory.favoriteAlarmSounds);
    try {
      final raw = await _methods.invokeMethod<dynamic>(
        'loadFavoriteAlarmSounds',
      );
      if (raw is! List) return const [];
      return raw.map((item) => item.toString()).toList();
    } on PlatformException {
      return const [];
    }
  }

  Future<void> saveFavoriteAlarmSounds(List<String> uris) async {
    final memory = _memory;
    if (memory != null) {
      memory.favoriteAlarmSounds = List<String>.of(uris);
      return;
    }
    try {
      await _methods.invokeMethod<dynamic>('saveFavoriteAlarmSounds', {
        'uris': uris,
      });
    } on PlatformException {
      // Favorites are a preference. The picker still updates on screen.
    }
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
    if (_memory != null) return Future<void>.value();
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
    if (_memory != null) return null;
    final raw = await _methods.invokeMethod<dynamic>('consumeClockIntent');
    if (raw == null) return null;
    return ClockLaunch.fromMap(_map(raw));
  }
}

/// Page-session alarm list used on Flutter Web. Not written to disk or
/// browser storage, and not connected to the Android alarm engine.
class _WebAlarmMemory {
  final List<AlarmItem> _alarms = [];
  int _nextId = 1;
  String planLibrary = '';
  String lastAlarmSound = '';
  List<String> favoriteAlarmSounds = const [];

  List<AlarmItem> getAlarms() => _alarms.map(_copy).toList();

  AlarmItem upsert(AlarmItem alarm) {
    final id = alarm.id > 0 ? alarm.id : _nextId++;
    if (id >= _nextId) _nextId = id + 1;
    final saved = _copy(alarm.copyWith(id: id));
    final index = _alarms.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _alarms[index] = saved;
    } else {
      _alarms.add(saved);
    }
    return _copy(saved);
  }

  void delete(int id) {
    _alarms.removeWhere((item) => item.id == id);
  }

  AlarmItem setEnabled(int id, bool enabled) {
    final index = _alarms.indexWhere((item) => item.id == id);
    if (index < 0) {
      throw PlatformException(
        code: 'not_found',
        message: 'Alarm $id was not found',
      );
    }
    final saved = _copy(_alarms[index].copyWith(enabled: enabled));
    _alarms[index] = saved;
    return _copy(saved);
  }

  AlarmItem _copy(AlarmItem alarm) {
    return alarm.copyWith(
      repeatDays: List<int>.from(alarm.repeatDays),
      weekTags: List<String>.from(alarm.weekTags),
      scheduleError: '',
    );
  }
}

Map<dynamic, dynamic> _map(Object? raw) {
  if (raw is Map) return Map<dynamic, dynamic>.from(raw);
  return const {};
}

List<Map<dynamic, dynamic>> _maps(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<dynamic, dynamic>.from(item))
      .toList();
}
