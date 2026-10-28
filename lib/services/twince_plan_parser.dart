import 'dart:convert';

import 'package:twince_alarm/models/imported_plan.dart';

const _weekdays = {
  'mon': 1,
  'tue': 2,
  'wed': 3,
  'thu': 4,
  'fri': 5,
  'sat': 6,
  'sun': 7,
};

/// Parses a Twince `Export JSON` document.
///
/// `endTime` is the only alarm time. `startTime` and `startSecond` are ignored.
/// Current mapping is even=Z and odd=F. Legacy exports declaring even=F and
/// odd=Z are accepted and converted to the current semantic mapping.
ImportedPlan parseTwincePlan(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw PlanImportException('Invalid JSON.');
  }
  if (decoded is! Map) {
    throw PlanImportException('Invalid JSON.');
  }
  final root = Map<String, Object?>.from(decoded);
  if (root['format'] != 'twince-plan') {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  final version = root['version'];
  if (version is! int || version != 1) {
    throw PlanImportException('Unsupported Plan version.');
  }
  final source = root['source'];
  if (source != null && source != 'twince') {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  final planRaw = root['plan'];
  if (planRaw is! Map) {
    throw PlanImportException('Missing Plan ID.');
  }
  final plan = Map<String, Object?>.from(planRaw);
  final planId = plan['id'];
  if (planId is! String || planId.trim().isEmpty) {
    throw PlanImportException('Missing Plan ID.');
  }
  final title = plan['title'];
  if (title is! String) {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  final modeRaw = plan['weekMode'];
  if (modeRaw != 'even_odd' && modeRaw != 'every') {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  final mode = modeRaw == 'every' ? PlanWeekMode.every : PlanWeekMode.evenOdd;
  final tasksRaw = plan['tasks'];
  if (tasksRaw is! List) {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  var legacyLabels = false;
  final reference = plan['weekReference'];
  if (reference is Map) {
    final evenLabel = reference['evenLabel'];
    final oddLabel = reference['oddLabel'];
    if (evenLabel == 'F' && oddLabel == 'Z') {
      legacyLabels = true;
    } else if ((evenLabel != null || oddLabel != null) &&
        (evenLabel != 'Z' || oddLabel != 'F')) {
      throw PlanImportException('Invalid Z/F week assignment.');
    }
  }
  final grouped = <String, List<_RawTask>>{};
  for (final item in tasksRaw) {
    if (item is! Map) {
      throw PlanImportException('Task has no title.');
    }
    final task = _readTask(Map<String, Object?>.from(item), mode, legacyLabels);
    grouped.putIfAbsent(task.id, () => []).add(task);
  }
  final tasks = grouped.entries
      .map((entry) => _merge(entry.key, entry.value, mode))
      .toList();
  return ImportedPlan(
    sourcePlanId: planId.trim(),
    title: title,
    weekMode: mode,
    tasks: tasks,
    sourceFormat: 'twince-plan',
    sourceVersion: version,
    exportedAt: root['exportedAt'] as String? ?? '',
    timezone: root['timezone'] as String? ?? '',
  );
}

class _RawTask {
  const _RawTask({
    required this.id,
    required this.title,
    required this.description,
    required this.hour,
    required this.minute,
    required this.days,
    required this.enabled,
    required this.week,
  });

  final String id;
  final String title;
  final String description;
  final int hour;
  final int minute;
  final List<int> days;
  final bool enabled;
  final PlanWeek? week;
}

_RawTask _readTask(
  Map<String, Object?> json,
  PlanWeekMode mode,
  bool legacyLabels,
) {
  final id = json['id'];
  if (id is! String || id.trim().isEmpty) {
    throw PlanImportException('Missing task ID.');
  }
  final title = json['title'];
  if (title is! String || title.trim().isEmpty) {
    throw PlanImportException('Task has no title.');
  }
  final time = _endTime(json['endTime']);
  final days = _days(json['days']);
  final enabledRaw = json['enabled'];
  if (enabledRaw != null && enabledRaw is! bool) {
    throw PlanImportException('Unsupported Twince Plan format.');
  }
  PlanWeek? week;
  if (mode == PlanWeekMode.evenOdd) {
    week = _week(json['weekType'], json['weekLabel'], legacyLabels);
  }
  final description = json['description'];
  return _RawTask(
    id: id.trim(),
    title: title,
    description: description is String ? description : '',
    hour: time.$1,
    minute: time.$2,
    days: days,
    enabled: enabledRaw as bool? ?? true,
    week: week,
  );
}

(int, int) _endTime(Object? raw) {
  if (raw is! String) {
    throw PlanImportException('Task has no valid end time.');
  }
  final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(raw);
  if (match == null) {
    throw PlanImportException('Task has no valid end time.');
  }
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}

List<int> _days(Object? raw) {
  if (raw is! List) {
    throw PlanImportException('Invalid weekday.');
  }
  final days = <int>[];
  for (final item in raw) {
    if (item is! String || !_weekdays.containsKey(item)) {
      throw PlanImportException('Invalid weekday.');
    }
    days.add(_weekdays[item]!);
  }
  days.sort();
  return days.toSet().toList()..sort();
}

PlanWeek _week(Object? type, Object? label, bool legacyLabels) {
  if (!legacyLabels && type == 'odd' && label == 'F') return PlanWeek.f;
  if (!legacyLabels && type == 'even' && label == 'Z') return PlanWeek.z;
  if (legacyLabels && type == 'odd' && label == 'Z') return PlanWeek.f;
  if (legacyLabels && type == 'even' && label == 'F') return PlanWeek.z;
  throw PlanImportException('Invalid Z/F week assignment.');
}

ImportedTask _merge(String id, List<_RawTask> parts, PlanWeekMode mode) {
  final first = parts.first;
  for (final part in parts) {
    final same =
        part.title == first.title &&
        part.description == first.description &&
        part.hour == first.hour &&
        part.minute == first.minute &&
        part.enabled == first.enabled &&
        _sameDays(part.days, first.days);
    if (!same) {
      throw PlanImportException('Invalid Z/F week assignment.');
    }
  }
  final weeks = <PlanWeek>[];
  if (mode == PlanWeekMode.evenOdd) {
    final seen = parts.map((part) => part.week).toSet();
    if (seen.contains(null) || seen.isEmpty) {
      throw PlanImportException('Invalid Z/F week assignment.');
    }
    if (seen.contains(PlanWeek.z)) weeks.add(PlanWeek.z);
    if (seen.contains(PlanWeek.f)) weeks.add(PlanWeek.f);
  }
  return ImportedTask(
    sourceTaskId: id,
    title: first.title,
    description: first.description,
    hour: first.hour,
    minute: first.minute,
    repeatDays: first.days,
    enabled: first.enabled,
    weekAssignments: weeks,
    alarmId: 0,
  );
}

bool _sameDays(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
