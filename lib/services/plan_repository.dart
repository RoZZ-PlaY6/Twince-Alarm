import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/models/imported_plan.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/services/plan_storage.dart';
import 'package:twince_alarm/services/plan_week.dart';
import 'package:twince_alarm/services/twince_plan_parser.dart';

class MemoryPlanStorage implements PlanStorage {
  String value = '';

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

abstract class PlanAlarmGateway {
  Future<AlarmItem> upsert(AlarmItem alarm);
  Future<void> delete(int id);
}

class BridgePlanAlarmGateway implements PlanAlarmGateway {
  @override
  Future<AlarmItem> upsert(AlarmItem alarm) =>
      AlarmBridge.instance.upsert(alarm);

  @override
  Future<void> delete(int id) => AlarmBridge.instance.delete(id);
}

class PlanRepository {
  PlanRepository({PlanStorage? storage, PlanAlarmGateway? alarms})
    : _storage = storage ?? createPlanStorage(),
      _alarms = alarms ?? BridgePlanAlarmGateway();

  final PlanStorage _storage;
  final PlanAlarmGateway _alarms;
  Future<void>? _loadInFlight;
  List<ImportedPlan> plans = const [];
  WeekCycle? weekCycle;

  bool get weekConfigured => weekCycle != null;

  bool isEvenWeekOn(DateTime now) {
    final cycle = weekCycle;
    if (cycle == null) {
      throw StateError('Current week parity has not been chosen');
    }
    return isEvenWeek(cycle, now);
  }

  Future<void> load() {
    final current = _loadInFlight;
    if (current != null) return current;
    final task = _readLibrary();
    _loadInFlight = task;
    return task.whenComplete(() {
      if (identical(_loadInFlight, task)) _loadInFlight = null;
    });
  }

  Future<void> _readLibrary() async {
    try {
      final raw = await _storage.read() ?? '';
      final document = decodePlanLibraryDocument(raw);
      plans = document.plans;
      weekCycle = document.weekCycle;
      if (raw.trim().isNotEmpty) {
        await _storage.write(encodePlanLibrary(plans, weekCycle: weekCycle));
        if (document.legacyMapping) {
          await reconcile(DateTime.now());
        }
      }
    } catch (_) {
      plans = const [];
      weekCycle = null;
    }
  }

  Future<void> setCurrentWeek({
    required bool even,
    required DateTime now,
  }) async {
    weekCycle = WeekCycle(anchorSaturday: saturdayOnOrBefore(now), even: even);
    await _storage.write(encodePlanLibrary(plans, weekCycle: weekCycle));
    await reconcile(now);
  }

  ImportPreview preview(String raw) {
    final parsed = parseTwincePlan(raw);
    final existing = _find(parsed.sourcePlanId);
    final existingIds =
        existing?.tasks.map((task) => task.sourceTaskId).toSet() ?? {};
    final nextIds = parsed.tasks.map((task) => task.sourceTaskId).toSet();
    final updated = nextIds.intersection(existingIds).length;
    final created = nextIds.difference(existingIds).length;
    final removed = existingIds.difference(nextIds).length;
    return ImportPreview(
      plan: parsed,
      created: created,
      updated: updated,
      removed: removed,
    );
  }

  Future<ImportedPlan> commit(ImportPreview preview) async {
    final existing = _find(preview.plan.sourcePlanId);
    final previous = {
      for (final task in existing?.tasks ?? const <ImportedTask>[])
        task.sourceTaskId: task,
    };
    final savedTasks = <ImportedTask>[];
    for (final task in preview.plan.tasks) {
      final alarmId =
          previous[task.sourceTaskId]?.alarmId ??
          stableAlarmId(preview.plan.sourcePlanId, task.sourceTaskId);
      final alarm = AlarmItem(
        id: alarmId,
        hour: task.hour,
        minute: task.minute,
        label: task.title,
        subtitle: task.description.trim().isEmpty
            ? 'Time to start your task'
            : task.description,
        enabled: task.enabled,
        vibrate: true,
        soundUri: '',
        repeatDays: task.repeatDays,
        weekTags: task.weekTags,
      );
      final saved = await _alarms.upsert(alarm);
      savedTasks.add(task.copyWith(alarmId: saved.id));
    }
    final kept = savedTasks.map((task) => task.sourceTaskId).toSet();
    for (final old in previous.values) {
      if (!kept.contains(old.sourceTaskId) && old.alarmId > 0) {
        await _alarms.delete(old.alarmId);
      }
    }
    final stored = preview.plan.copyWith(tasks: savedTasks);
    final next = [
      for (final plan in plans)
        if (plan.sourcePlanId != stored.sourcePlanId) plan,
      stored,
    ];
    plans = next;
    await _persist();
    await reconcile(DateTime.now());
    return stored;
  }

  Future<void> reconcile(DateTime now) async {
    dateOnly(now);
    for (final plan in plans) {
      for (final task in plan.tasks) {
        final alarmId = task.alarmId > 0
            ? task.alarmId
            : stableAlarmId(plan.sourcePlanId, task.sourceTaskId);
        await _alarms.upsert(_alarmFor(task, alarmId));
      }
    }
  }

  Future<void> deletePlan(String planId) async {
    final existing = _find(planId);
    if (existing == null) return;
    for (final task in existing.tasks) {
      if (task.alarmId > 0) await _alarms.delete(task.alarmId);
    }
    plans = [
      for (final plan in plans)
        if (plan.sourcePlanId != planId) plan,
    ];
    await _persist();
  }

  Future<void> _persist() {
    return _storage.write(encodePlanLibrary(plans, weekCycle: weekCycle));
  }

  AlarmItem _alarmFor(ImportedTask task, int alarmId) {
    return AlarmItem(
      id: alarmId,
      hour: task.hour,
      minute: task.minute,
      label: task.title,
      subtitle: task.description.trim().isEmpty
          ? 'Time to start your task'
          : task.description,
      enabled: task.enabled,
      vibrate: true,
      soundUri: '',
      repeatDays: task.repeatDays,
      weekTags: task.weekTags,
    );
  }

  ImportedPlan? _find(String id) {
    for (final plan in plans) {
      if (plan.sourcePlanId == id) return plan;
    }
    return null;
  }
}

int stableAlarmId(String planId, String taskId) {
  var hash = 17;
  for (final unit in '$planId\u0000$taskId'.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  if (hash < 100000) hash += 100000;
  return hash;
}
