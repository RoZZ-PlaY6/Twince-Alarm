class AlarmItem {
  const AlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.vibrate,
    required this.soundUri,
    required this.repeatDays,
    this.snoozeUntil = 0,
    this.scheduleError = '',
  });

  final int id;
  final int hour;
  final int minute;
  final String label;
  final String subtitle;
  final bool enabled;
  final bool vibrate;
  final String soundUri;
  final List<int> repeatDays;
  final int snoozeUntil;
  final String scheduleError;

  AlarmItem copyWith({
    int? id,
    int? hour,
    int? minute,
    String? label,
    String? subtitle,
    bool? enabled,
    bool? vibrate,
    String? soundUri,
    List<int>? repeatDays,
    int? snoozeUntil,
    String? scheduleError,
  }) {
    return AlarmItem(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      subtitle: subtitle ?? this.subtitle,
      enabled: enabled ?? this.enabled,
      vibrate: vibrate ?? this.vibrate,
      soundUri: soundUri ?? this.soundUri,
      repeatDays: repeatDays ?? this.repeatDays,
      snoozeUntil: snoozeUntil ?? this.snoozeUntil,
      scheduleError: scheduleError ?? this.scheduleError,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'label': label,
      'subtitle': subtitle,
      'enabled': enabled,
      'vibrate': vibrate,
      'soundUri': soundUri,
      'repeatDays': repeatDays,
    };
  }

  static AlarmItem fromMap(Map<dynamic, dynamic> map) {
    return AlarmItem(
      id: _asInt(map['id']),
      hour: _asInt(map['hour']),
      minute: _asInt(map['minute']),
      label: (map['label'] as String?)?.trim().isNotEmpty == true
          ? (map['label'] as String).trim()
          : 'Alarm',
      subtitle: (map['subtitle'] as String?)?.trim().isNotEmpty == true
          ? (map['subtitle'] as String).trim()
          : 'Time to start your task',
      enabled: map['enabled'] as bool? ?? true,
      vibrate: map['vibrate'] as bool? ?? true,
      soundUri: map['soundUri'] as String? ?? '',
      repeatDays: _asIntList(map['repeatDays']),
      snoozeUntil: _asInt(map['snoozeUntil']),
      scheduleError: map['scheduleError'] as String? ?? '',
    );
  }
}

class AlarmSound {
  const AlarmSound({required this.name, required this.uri});

  final String name;
  final String uri;

  static AlarmSound fromMap(Map<dynamic, dynamic> map) {
    return AlarmSound(
      name: map['name'] as String? ?? 'Alarm tone',
      uri: map['uri'] as String? ?? '',
    );
  }
}

class AlarmPermissions {
  const AlarmPermissions({
    required this.notifications,
    required this.exactAlarm,
    required this.fullScreenIntent,
  });

  final bool notifications;
  final bool exactAlarm;
  final bool fullScreenIntent;

  static const granted = AlarmPermissions(
    notifications: true,
    exactAlarm: true,
    fullScreenIntent: true,
  );

  static AlarmPermissions fromMap(Map<dynamic, dynamic> map) {
    return AlarmPermissions(
      notifications: map['notifications'] as bool? ?? false,
      exactAlarm: map['exactAlarm'] as bool? ?? false,
      fullScreenIntent: map['fullScreenIntent'] as bool? ?? false,
    );
  }
}

class AlarmEvent {
  const AlarmEvent({
    required this.type,
    required this.alarmId,
    required this.snoozeMinutes,
    required this.label,
  });

  final String type;
  final int alarmId;
  final int snoozeMinutes;
  final String label;

  String get message {
    switch (type) {
      case 'snooze':
        return 'Snoozed $snoozeMinutes min';
      case 'restart':
        return 'Alarm restarted';
      case 'dismiss':
        return 'Alarm dismissed';
      default:
        return 'Alarm $type';
    }
  }

  static AlarmEvent fromMap(Map<dynamic, dynamic> map) {
    final type = (map['type'] ?? map['event']) as String? ?? '';
    return AlarmEvent(
      type: type,
      alarmId: _asInt(map['alarmId']),
      snoozeMinutes: _asInt(map['snoozeMinutes']),
      label: map['label'] as String? ?? '',
    );
  }
}

class ClockLaunch {
  const ClockLaunch({
    required this.action,
    required this.hour,
    required this.minute,
    required this.label,
    required this.skipUi,
    required this.vibrate,
    required this.soundUri,
    required this.repeatDays,
  });

  final String action;
  final int hour;
  final int minute;
  final String label;
  final bool skipUi;
  final bool vibrate;
  final String soundUri;
  final List<int> repeatDays;

  bool get isSetAlarm => action == 'android.intent.action.SET_ALARM';

  static ClockLaunch fromMap(Map<dynamic, dynamic> map) {
    return ClockLaunch(
      action: map['action'] as String? ?? '',
      hour: _asInt(map['hour'], fallback: -1),
      minute: _asInt(map['minute'], fallback: -1),
      label: map['label'] as String? ?? '',
      skipUi: map['skipUi'] as bool? ?? false,
      vibrate: map['vibrate'] as bool? ?? true,
      soundUri: map['soundUri'] as String? ?? '',
      repeatDays: _asIntList(map['repeatDays']),
    );
  }
}

/// Next local trigger. Monday = 1 … Sunday = 7. Native scheduling is authoritative.
DateTime? nextTrigger(AlarmItem alarm, DateTime from) {
  if (!alarm.enabled) return null;
  DateTime at(DateTime day) {
    return DateTime(day.year, day.month, day.day, alarm.hour, alarm.minute);
  }

  if (alarm.repeatDays.isEmpty) {
    final today = at(from);
    if (today.isAfter(from)) return today;
    final tomorrow = DateTime(from.year, from.month, from.day).add(const Duration(days: 1));
    return at(tomorrow);
  }
  for (var offset = 0; offset <= 7; offset++) {
    final day = DateTime(from.year, from.month, from.day).add(Duration(days: offset));
    final when = at(day);
    if (alarm.repeatDays.contains(when.weekday) && when.isAfter(from)) return when;
  }
  return null;
}

String repeatLabel(List<int> days) {
  if (days.isEmpty) return 'Once';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final sorted = [...days]..sort();
  final key = sorted.join();
  if (key == '12345') return 'Weekdays';
  if (key == '1234567') return 'Every day';
  if (key == '67') return 'Weekends';
  return sorted.map((day) => names[day - 1]).join(' ');
}

String formatClock(int hour, int minute, {required bool use24}) {
  final minutes = minute.toString().padLeft(2, '0');
  if (use24) return '${hour.toString().padLeft(2, '0')}:$minutes';
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:$minutes $period';
}

String formatRingTime(int hour, int minute, {required bool use24}) {
  final minutes = minute.toString().padLeft(2, '0');
  if (use24) return '${hour.toString().padLeft(2, '0')}:$minutes';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '${hour12.toString().padLeft(2, '0')}:$minutes';
}

String? ringPeriod(int hour, {required bool use24}) {
  if (use24) return null;
  return hour >= 12 ? 'PM' : 'AM';
}

const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatDate(DateTime time) {
  return '${weekdays[time.weekday - 1]}, ${months[time.month - 1]} ${time.day}';
}

String whenLabel(DateTime next, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(next.year, next.month, next.day);
  if (target == today) return 'Today';
  if (target == today.add(const Duration(days: 1))) return 'Tomorrow';
  return weekdays[next.weekday - 1];
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

List<int> _asIntList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<num>().map((item) => item.toInt()).where((day) => day >= 1 && day <= 7).toList();
}
