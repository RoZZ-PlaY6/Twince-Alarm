import 'dart:convert';

class PlanImportException implements Exception {
  PlanImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum PlanWeekMode { evenOdd, every }

enum PlanWeek { z, f }

class ImportedTask {
  const ImportedTask({
    required this.sourceTaskId,
    required this.title,
    required this.description,
    required this.hour,
    required this.minute,
    required this.repeatDays,
    required this.enabled,
    required this.weekAssignments,
    required this.alarmId,
  });

  final String sourceTaskId;
  final String title;
  final String description;
  final int hour;
  final int minute;
  final List<int> repeatDays;
  final bool enabled;
  final List<PlanWeek> weekAssignments;
  final int alarmId;

  List<String> get weekTags {
    if (weekAssignments.length != 1) return const [];
    return [weekAssignments.single == PlanWeek.z ? 'Z' : 'F'];
  }

  String get weekText {
    if (weekAssignments.isEmpty) return 'Every week';
    if (weekAssignments.length == 2) return 'Z + F';
    return weekAssignments.single == PlanWeek.z ? 'Z' : 'F';
  }

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ImportedTask copyWith({int? alarmId}) {
    return ImportedTask(
      sourceTaskId: sourceTaskId,
      title: title,
      description: description,
      hour: hour,
      minute: minute,
      repeatDays: repeatDays,
      enabled: enabled,
      weekAssignments: weekAssignments,
      alarmId: alarmId ?? this.alarmId,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourceTaskId': sourceTaskId,
      'title': title,
      'description': description,
      'hour': hour,
      'minute': minute,
      'repeatDays': repeatDays,
      'enabled': enabled,
      'weekAssignments': weekAssignments.map((week) => week.name).toList(),
      'alarmId': alarmId,
    };
  }

  static ImportedTask fromJson(Map<String, Object?> json) {
    return ImportedTask(
      sourceTaskId: json['sourceTaskId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      repeatDays:
          (json['repeatDays'] as List?)
              ?.map((day) => (day as num).toInt())
              .toList() ??
          const [],
      enabled: json['enabled'] as bool? ?? true,
      weekAssignments:
          (json['weekAssignments'] as List?)
              ?.map((name) => name == 'f' ? PlanWeek.f : PlanWeek.z)
              .toList() ??
          const [],
      alarmId: (json['alarmId'] as num?)?.toInt() ?? 0,
    );
  }
}

class ImportedPlan {
  const ImportedPlan({
    required this.sourcePlanId,
    required this.title,
    required this.weekMode,
    required this.tasks,
    required this.sourceFormat,
    required this.sourceVersion,
    this.exportedAt = '',
    this.timezone = '',
  });

  final String sourcePlanId;
  final String title;
  final PlanWeekMode weekMode;
  final List<ImportedTask> tasks;
  final String sourceFormat;
  final int sourceVersion;
  final String exportedAt;
  final String timezone;

  String get typeLabel =>
      weekMode == PlanWeekMode.every ? 'ETC · Every week' : 'University · Z/F';

  ImportedPlan copyWith({List<ImportedTask>? tasks}) {
    return ImportedPlan(
      sourcePlanId: sourcePlanId,
      title: title,
      weekMode: weekMode,
      tasks: tasks ?? this.tasks,
      sourceFormat: sourceFormat,
      sourceVersion: sourceVersion,
      exportedAt: exportedAt,
      timezone: timezone,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourcePlanId': sourcePlanId,
      'title': title,
      'weekMode': weekMode.name,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'sourceFormat': sourceFormat,
      'sourceVersion': sourceVersion,
      'exportedAt': exportedAt,
      'timezone': timezone,
    };
  }

  static ImportedPlan fromJson(Map<String, Object?> json) {
    return ImportedPlan(
      sourcePlanId: json['sourcePlanId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      weekMode: json['weekMode'] == 'every'
          ? PlanWeekMode.every
          : PlanWeekMode.evenOdd,
      tasks: (json['tasks'] as List? ?? const [])
          .whereType<Map>()
          .map((task) => ImportedTask.fromJson(Map<String, Object?>.from(task)))
          .toList(),
      sourceFormat: json['sourceFormat'] as String? ?? 'twince-plan',
      sourceVersion: (json['sourceVersion'] as num?)?.toInt() ?? 1,
      exportedAt: json['exportedAt'] as String? ?? '',
      timezone: json['timezone'] as String? ?? '',
    );
  }
}

class ImportPreview {
  const ImportPreview({
    required this.plan,
    required this.created,
    required this.updated,
    required this.removed,
  });

  final ImportedPlan plan;
  final int created;
  final int updated;
  final int removed;

  bool get replacesExisting =>
      updated + removed > 0 || created == 0 && updated > 0;
}

String encodePlanLibrary(List<ImportedPlan> plans) {
  return jsonEncode({'plans': plans.map((plan) => plan.toJson()).toList()});
}

List<ImportedPlan> decodePlanLibrary(String raw) {
  if (raw.trim().isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const [];
  final plans = decoded['plans'];
  if (plans is! List) return const [];
  return plans
      .whereType<Map>()
      .map((plan) => ImportedPlan.fromJson(Map<String, Object?>.from(plan)))
      .toList();
}
