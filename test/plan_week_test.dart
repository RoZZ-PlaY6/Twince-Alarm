import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/models/imported_plan.dart';
import 'package:twince_alarm/services/plan_repository.dart';
import 'package:twince_alarm/services/plan_week.dart';
import 'package:twince_alarm/services/twince_plan_parser.dart';

class _MemoryAlarms implements PlanAlarmGateway {
  final saved = <int, AlarmItem>{};

  @override
  Future<void> delete(int id) async {
    saved.remove(id);
  }

  @override
  Future<AlarmItem> upsert(AlarmItem alarm) async {
    saved[alarm.id] = alarm;
    return alarm;
  }
}

void main() {
  group('UI rule: Z = Even week (هفته زوج), F = Odd week (هفته فرد)', () {
    test('WeekCycle.label pairs Even with Z and Odd with F', () {
      expect(
        WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: true).label,
        'Even (Z)',
      );
      expect(
        WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: false).label,
        'Odd (F)',
      );
    });

    test('currentWeekCaption pairs Even with Z/زوج and Odd with F/فرد', () {
      final even = WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: true);
      expect(
        currentWeekCaption(even, DateTime(2026, 10, 26)),
        'Current week: Even (Z)',
      );
      final odd = WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: false);
      expect(
        currentWeekCaption(odd, DateTime(2026, 10, 26)),
        'Current week: Odd (F)',
      );
    });

    test('ImportedTask pairs PlanWeek.z with Z/Even and PlanWeek.f with F/Odd', () {
      final z = ImportedTask(
        sourceTaskId: 't1',
        title: 'Task',
        description: '',
        hour: 8,
        minute: 0,
        repeatDays: const [1],
        enabled: true,
        weekAssignments: const [PlanWeek.z],
        alarmId: 1,
      );
      expect(z.weekTags, ['Z']);
      expect(z.weekText, 'Even (Z)');

      final f = ImportedTask(
        sourceTaskId: 't2',
        title: 'Task',
        description: '',
        hour: 9,
        minute: 0,
        repeatDays: const [2],
        enabled: true,
        weekAssignments: const [PlanWeek.f],
        alarmId: 2,
      );
      expect(f.weekTags, ['F']);
      expect(f.weekText, 'Odd (F)');

      final both = ImportedTask(
        sourceTaskId: 't3',
        title: 'Task',
        description: '',
        hour: 10,
        minute: 0,
        repeatDays: const [3],
        enabled: true,
        weekAssignments: const [PlanWeek.z, PlanWeek.f],
        alarmId: 3,
      );
      expect(both.weekTags, ['both']);
      expect(both.weekText, 'Even (Z) + Odd (F)');

      // JSON round trip keeps the pairing.
      expect(ImportedTask.fromJson(z.toJson()).weekTags, ['Z']);
      expect(ImportedTask.fromJson(f.toJson()).weekTags, ['F']);
    });

    test('recurrenceOf maps Z/even to Even and F/odd to Odd', () {
      expect(recurrenceOf(const ['Z']), PlanRecurrence.even);
      expect(recurrenceOf(const ['even']), PlanRecurrence.even);
      expect(recurrenceOf(const ['F']), PlanRecurrence.odd);
      expect(recurrenceOf(const ['odd']), PlanRecurrence.odd);
      expect(recurrenceOf(const ['both']), PlanRecurrence.both);
      expect(recurrenceOf(const ['every']), PlanRecurrence.both);
      expect(recurrenceOf(const []), isNull);
      expect(recurrenceOf(const ['nope']), isNull);
    });

    test('recurrenceEligible executes Even plans only in Z weeks', () {
      expect(recurrenceEligible(PlanRecurrence.even, true), isTrue);
      expect(recurrenceEligible(PlanRecurrence.even, false), isFalse);
      expect(recurrenceEligible(PlanRecurrence.odd, true), isFalse);
      expect(recurrenceEligible(PlanRecurrence.odd, false), isTrue);
      expect(recurrenceEligible(PlanRecurrence.both, true), isTrue);
      expect(recurrenceEligible(PlanRecurrence.both, false), isTrue);
    });
  });

  group('Saturday–Friday week boundary flips parity', () {
    final anchor = DateTime(2026, 10, 24); // Saturday
    late WeekCycle cycle;

    setUp(() {
      cycle = WeekCycle(anchorSaturday: anchor, even: true);
    });

    test('anchor Saturday–Friday week keeps the chosen parity', () {
      expect(isEvenWeek(cycle, DateTime(2026, 10, 24)), isTrue); // Saturday
      expect(isEvenWeek(cycle, DateTime(2026, 10, 26)), isTrue); // Monday
      expect(isEvenWeek(cycle, DateTime(2026, 10, 30)), isTrue); // Friday
    });

    test('each later Saturday flips the parity', () {
      expect(isEvenWeek(cycle, DateTime(2026, 10, 31)), isFalse); // next Saturday
      expect(isEvenWeek(cycle, DateTime(2026, 11, 2)), isFalse); // Monday
      expect(isEvenWeek(cycle, DateTime(2026, 11, 7)), isTrue); // flips back
      expect(isEvenWeek(cycle, DateTime(2026, 11, 8)), isTrue);
    });

    test('earlier Saturdays flip the parity too', () {
      expect(isEvenWeek(cycle, DateTime(2026, 10, 17)), isFalse);
      expect(isEvenWeek(cycle, DateTime(2026, 10, 10)), isTrue);
    });

    test('parity is normalized across month and year boundaries', () {
      final boundary = WeekCycle(
        anchorSaturday: DateTime(2026, 12, 26, 23, 59),
        even: true,
      );
      expect(isEvenWeek(boundary, DateTime(2026, 12, 31, 23, 59)), isTrue);
      expect(isEvenWeek(boundary, DateTime(2027, 1, 1, 0, 1)), isTrue);
      expect(isEvenWeek(boundary, DateTime(2027, 1, 2)), isFalse);
      expect(isEvenWeek(boundary, DateTime(2027, 1, 9)), isTrue);
      expect(isEvenWeek(boundary, DateTime(2026, 12, 19)), isFalse);
    });

    test('odd anchor (F) inverts every result', () {
      final odd = WeekCycle(anchorSaturday: anchor, even: false);
      expect(isEvenWeek(odd, DateTime(2026, 10, 26)), isFalse);
      expect(isEvenWeek(odd, DateTime(2026, 10, 31)), isTrue);
      expect(isEvenWeek(odd, DateTime(2026, 11, 7)), isFalse);
    });
  });

  group('Plans fire only in their configured parity week', () {
    late WeekCycle cycle;

    setUp(() {
      cycle = WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: true);
    });

    test('Z-plan Monday alarm fires in an even (Z) week', () {
      final z = nextLocalAlarm(
        from: DateTime(2026, 10, 24, 6),
        hour: 7,
        minute: 30,
        repeatDays: const [DateTime.monday],
        weekTags: const ['Z'],
        cycle: cycle,
      );
      expect(z, DateTime(2026, 10, 26, 7, 30));
      expect(isEvenWeek(cycle, z!), isTrue);
    });

    test('F-plan Tuesday alarm skips even weeks and fires in an odd (F) week', () {
      final f = nextLocalAlarm(
        from: DateTime(2026, 10, 24, 6),
        hour: 14,
        minute: 0,
        repeatDays: const [DateTime.tuesday],
        weekTags: const ['F'],
        cycle: cycle,
      );
      // 2026-10-27 is a Tuesday inside the even (Z) week -> skipped.
      expect(f, DateTime(2026, 11, 3, 14, 0));
      expect(isEvenWeek(cycle, f!), isFalse);
    });

    test('parity is evaluated at the actual firing date across Saturday', () {
      final fridayNight = DateTime(2026, 10, 30, 20); // still even week
      final z = nextLocalAlarm(
        from: fridayNight,
        hour: 7,
        minute: 0,
        repeatDays: const [DateTime.monday],
        weekTags: const ['Z'],
        cycle: cycle,
      );
      // 2026-11-02 is Monday inside the odd (F) week -> skipped;
      // 2026-11-09 is Monday inside the next even (Z) week.
      expect(z, DateTime(2026, 11, 9, 7, 0));
      expect(isEvenWeek(cycle, z!), isTrue);

      final f = nextLocalAlarm(
        from: fridayNight,
        hour: 14,
        minute: 0,
        repeatDays: const [DateTime.tuesday],
        weekTags: const ['F'],
        cycle: cycle,
      );
      expect(f, DateTime(2026, 11, 3, 14, 0));
      expect(isEvenWeek(cycle, f!), isFalse);
    });

    test('Z plan never fires in an F week and F plan never fires in a Z week', () {
      final from = DateTime(2026, 10, 31, 8); // odd (F) week, after Saturday flip
      final z = nextLocalAlarm(
        from: from,
        hour: 7,
        minute: 0,
        repeatDays: const [DateTime.monday],
        weekTags: const ['Z'],
        cycle: cycle,
      )!;
      expect(z, DateTime(2026, 11, 9, 7, 0));
      expect(isEvenWeek(cycle, z), isTrue);

      final f = nextLocalAlarm(
        from: from,
        hour: 14,
        minute: 0,
        repeatDays: const [DateTime.tuesday],
        weekTags: const ['F'],
        cycle: cycle,
      )!;
      expect(f, DateTime(2026, 11, 3, 14, 0));
      expect(isEvenWeek(cycle, f), isFalse);
    });
  });

  group('setCurrentWeek persists Z = Even / F = Odd across reloads', () {
    test('choosing even (Z) makes Z-tagged plans eligible and survives reload', () async {
      final storage = MemoryPlanStorage();
      final repo = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await repo.setCurrentWeek(even: true, now: DateTime(2026, 10, 26, 15));
      expect(repo.weekCycle!.anchorSaturday, DateTime(2026, 10, 24));
      expect(repo.weekCycle!.even, isTrue);
      expect(repo.isEvenWeekOn(DateTime(2026, 10, 26)), isTrue);
      expect(repo.isEvenWeekOn(DateTime(2026, 10, 31)), isFalse);

      expect(
        recurrenceEligible(PlanRecurrence.even, repo.isEvenWeekOn(DateTime(2026, 10, 26))),
        isTrue,
      );
      expect(
        recurrenceEligible(PlanRecurrence.odd, repo.isEvenWeekOn(DateTime(2026, 10, 26))),
        isFalse,
      );

      final reloaded = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await reloaded.load();
      expect(reloaded.weekConfigured, isTrue);
      expect(reloaded.weekCycle!.even, isTrue);
      expect(reloaded.weekCycle!.anchorSaturday, DateTime(2026, 10, 24));
      expect(
        recurrenceEligible(PlanRecurrence.even, reloaded.isEvenWeekOn(DateTime(2026, 10, 26))),
        isTrue,
      );
    });

    test('choosing odd (F) makes F-tagged plans eligible and survives reload', () async {
      final storage = MemoryPlanStorage();
      final repo = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await repo.setCurrentWeek(even: false, now: DateTime(2026, 10, 28, 9));
      expect(repo.weekCycle!.anchorSaturday, DateTime(2026, 10, 24));
      expect(repo.weekCycle!.even, isFalse);
      expect(repo.isEvenWeekOn(DateTime(2026, 10, 26)), isFalse); // anchor week is odd

      expect(
        recurrenceEligible(PlanRecurrence.odd, repo.isEvenWeekOn(DateTime(2026, 10, 26))),
        isTrue,
      );
      expect(
        recurrenceEligible(PlanRecurrence.even, repo.isEvenWeekOn(DateTime(2026, 10, 26))),
        isFalse,
      );

      final reloaded = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await reloaded.load();
      expect(reloaded.weekCycle!.even, isFalse);
      expect(
        recurrenceEligible(PlanRecurrence.odd, reloaded.isEvenWeekOn(DateTime(2026, 10, 26))),
        isTrue,
      );
    });
  });

  group('Migration: older data saved F as Even / Z as Odd is corrected to Z = Even, F = Odd', () {
    Map<String, Object?> legacyPlan({required int weekParityMapping}) {
      return {
        'weekParityMapping': weekParityMapping,
        'plans': [
          {
            'sourcePlanId': 'legacy',
            'title': 'Legacy',
            'weekMode': 'evenOdd',
            'tasks': [
              {
                'sourceTaskId': 'even-was-f',
                'title': 'Even',
                'description': '',
                'hour': 8,
                'minute': 0,
                'repeatDays': [1],
                'enabled': true,
                // Legacy: 'F' meant the Even week.
                'weekAssignments': ['f'],
                'alarmId': 101,
              },
              {
                'sourceTaskId': 'odd-was-z',
                'title': 'Odd',
                'description': '',
                'hour': 9,
                'minute': 0,
                'repeatDays': [1],
                'enabled': true,
                // Legacy: 'Z' meant the Odd week.
                'weekAssignments': ['z'],
                'alarmId': 102,
              },
            ],
            'sourceFormat': 'twince-plan',
            'sourceVersion': 1,
          },
        ],
        'weekCycle': {'anchorSaturday': '2026-10-24', 'even': true},
      };
    }

    test('weekParityMapping 1 swaps legacy tags to the current rule', () {
      final doc = decodePlanLibraryDocument(jsonEncode(legacyPlan(weekParityMapping: 1)));
      expect(doc.legacyMapping, isTrue);
      final tasks = doc.plans.single.tasks;
      expect(tasks[0].weekTags, ['Z']); // legacy Even(F) -> Even (Z)
      expect(tasks[0].weekText, 'Even (Z)');
      expect(tasks[1].weekTags, ['F']); // legacy Odd(Z) -> Odd (F)
      expect(tasks[1].weekText, 'Odd (F)');
    });

    test('missing weekParityMapping is treated as legacy and migrated', () {
      final raw = jsonEncode({
        'plans': legacyPlan(weekParityMapping: 2)['plans'],
        'weekCycle': {'anchorSaturday': '2026-10-24', 'even': true},
      });
      final doc = decodePlanLibraryDocument(raw);
      expect(doc.legacyMapping, isTrue);
      expect(doc.plans.single.tasks[0].weekTags, ['Z']);
      expect(doc.plans.single.tasks[0].weekText, 'Even (Z)');
    });

    test('weekParityMapping 2 keeps current tags unchanged', () {
      final doc = decodePlanLibraryDocument(
        jsonEncode({
          'weekParityMapping': 2,
          'plans': [
            {
              'sourcePlanId': 'current',
              'title': 'Current',
              'weekMode': 'evenOdd',
              'tasks': [
                {
                  'sourceTaskId': 'even-z',
                  'title': 'Even',
                  'hour': 8,
                  'minute': 0,
                  'repeatDays': [1],
                  'enabled': true,
                  'weekAssignments': ['z'],
                  'alarmId': 201,
                },
              ],
              'sourceFormat': 'twince-plan',
              'sourceVersion': 1,
            },
          ],
        }),
      );
      expect(doc.legacyMapping, isFalse);
      expect(doc.plans.single.tasks.single.weekTags, ['Z']);
    });

    test('PlanRepository.load migrates legacy data and re-saves mapping 2 without re-inverting', () async {
      final storage = MemoryPlanStorage();
      storage.value = jsonEncode(legacyPlan(weekParityMapping: 1));
      final repo = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await repo.load();

      expect(repo.weekConfigured, isTrue);
      expect(repo.plans.single.tasks[0].weekTags, ['Z']);
      expect(repo.plans.single.tasks[0].weekText, 'Even (Z)');
      expect(repo.plans.single.tasks[1].weekTags, ['F']);
      expect(repo.plans.single.tasks[1].weekText, 'Odd (F)');

      // Re-saved with the current mapping; a second load must not invert again.
      expect(storage.value, contains('"weekParityMapping":2'));
      final again = PlanRepository(storage: storage, alarms: _MemoryAlarms());
      await again.load();
      expect(again.plans.single.tasks[0].weekTags, ['Z']);
      expect(again.plans.single.tasks.last.weekTags, ['F']);
    });
  });

  group('Import parser preserves Z = Even / F = Odd', () {
    test('evenLabel Z / oddLabel F maps to PlanWeek.z / PlanWeek.f', () {
      final plan = parseTwincePlan('{"format":"twince-plan","version":1,"source":"twince",'
          '"plan":{"id":"p","title":"T","weekMode":"even_odd",'
          '"weekReference":{"evenLabel":"Z","oddLabel":"F"},'
          '"tasks":[{"id":"a","title":"A","endTime":"08:00","days":["mon"],'
          '"weekType":"even","weekLabel":"Z","enabled":true}]}}');
      final task = plan.tasks.single;
      expect(task.weekAssignments, [PlanWeek.z]);
      expect(task.weekTags, ['Z']);
      expect(task.weekText, 'Even (Z)');
    });

    test('legacy import (evenLabel F / oddLabel Z) is converted to the current rule', () {
      final plan = parseTwincePlan('{"format":"twince-plan","version":1,"source":"twince",'
          '"plan":{"id":"p","title":"T","weekMode":"even_odd",'
          '"weekReference":{"evenLabel":"F","oddLabel":"Z"},'
          '"tasks":[{"id":"a","title":"A","endTime":"08:00","days":["mon"],'
          '"weekType":"even","weekLabel":"F","enabled":true}]}}');
      expect(plan.tasks.single.weekAssignments, [PlanWeek.z]);
      expect(plan.tasks.single.weekTags, ['Z']);
      expect(plan.tasks.single.weekText, 'Even (Z)');
    });
  });
}
