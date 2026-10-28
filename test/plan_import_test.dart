import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/models/imported_plan.dart';
import 'package:twince_alarm/screens/plan_screen.dart';
import 'package:twince_alarm/services/plan_repository.dart';
import 'package:twince_alarm/services/plan_week.dart';
import 'package:twince_alarm/services/twince_plan_parser.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class _MemoryAlarms implements PlanAlarmGateway {
  final saved = <int, AlarmItem>{};
  final upserts = <int>[];

  @override
  Future<void> delete(int id) async {
    saved.remove(id);
  }

  @override
  Future<AlarmItem> upsert(AlarmItem alarm) async {
    upserts.add(alarm.id);
    saved[alarm.id] = alarm;
    return alarm;
  }
}

String _plan({
  String id = 'plan-1',
  String mode = 'even_odd',
  String title = 'University',
  required List<Map<String, Object?>> tasks,
}) {
  return jsonEncode({
    'format': 'twince-plan',
    'version': 1,
    'source': 'twince',
    'exportedAt': '2026-10-25T08:00:00.000Z',
    'timezone': '+03:30',
    'plan': {
      'id': id,
      'title': title,
      'weekMode': mode,
      'weekReference': {'evenLabel': 'Z', 'oddLabel': 'F'},
      'tasks': [
        for (final task in tasks)
          {
            'id': task['id'],
            'title': task['title'],
            'description': task['description'] ?? '',
            'endTime': task['endTime'],
            'startTime': '06:00',
            'startSecond': 21600,
            'days': task['days'],
            'enabled': task['enabled'] ?? true,
            if (task['weekType'] != null) 'weekType': task['weekType'],
            if (task['weekLabel'] != null) 'weekLabel': task['weekLabel'],
          },
      ],
    },
  });
}

String _sample() {
  return _plan(
    title: 'تمرین',
    tasks: [
      {
        'id': 'z1',
        'title': 'تمرین صبح',
        'description': 'توضیح',
        'endTime': '07:30',
        'days': ['mon'],
        'weekType': 'even',
        'weekLabel': 'Z',
      },
      {
        'id': 'f1',
        'title': 'Lab',
        'endTime': '14:00',
        'days': ['tue', 'thu'],
        'weekType': 'odd',
        'weekLabel': 'F',
      },
      {
        'id': 'both',
        'title': 'Studio',
        'endTime': '18:15',
        'days': ['wed'],
        'weekType': 'even',
        'weekLabel': 'Z',
      },
      {
        'id': 'both',
        'title': 'Studio',
        'endTime': '18:15',
        'days': ['wed'],
        'weekType': 'odd',
        'weekLabel': 'F',
      },
    ],
  );
}

void main() {
  test(
    'a chosen Saturday week stays through Friday and flips the next Saturday',
    () {
      final anchor = DateTime(2026, 10, 24);
      expect(anchor.weekday, DateTime.saturday);
      final cycle = WeekCycle(anchorSaturday: anchor, even: true);
      expect(isEvenWeek(cycle, DateTime(2026, 10, 24)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2026, 10, 25)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2026, 10, 30)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2026, 10, 31)), isFalse);
      expect(isEvenWeek(cycle, DateTime(2026, 11, 7)), isTrue);
      expect(
        currentWeekCaption(cycle, DateTime(2026, 10, 26)),
        contains('Even (Z)'),
      );
      expect(
        currentWeekCaption(cycle, DateTime(2026, 10, 31)),
        contains('Odd (F)'),
      );
    },
  );

  test(
    'parity uses normalized calendar dates across month and year boundaries',
    () {
      final cycle = WeekCycle(
        anchorSaturday: DateTime(2026, 12, 26, 23, 59),
        even: true,
      );
      expect(isEvenWeek(cycle, DateTime(2026, 12, 31, 23, 59)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2027, 1, 1, 0, 1)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2027, 1, 2)), isFalse);
      expect(isEvenWeek(cycle, DateTime(2027, 1, 9)), isTrue);
      expect(isEvenWeek(cycle, DateTime(2026, 12, 19)), isFalse);
    },
  );

  test('invalid or missing anchors do not silently produce a parity', () {
    expect(WeekCycle.fromJson(null), isNull);
    expect(
      WeekCycle.fromJson({'anchorSaturday': '2026-02-30', 'even': true}),
      isNull,
    );
    expect(
      nextLocalAlarm(
        from: DateTime(2026, 10, 24, 6),
        hour: 7,
        minute: 0,
        repeatDays: const [DateTime.monday],
        weekTags: const ['F'],
      ),
      isNull,
    );
    expect(recurrenceOf(const ['every']), PlanRecurrence.both);
    expect(
      () =>
          PlanRepository(storage: MemoryPlanStorage())
              .isEvenWeekOn(DateTime(2026, 10, 24)),
      throwsStateError,
    );
  });
  test('legacy saved Plans migrate F-even/Z-odd tags safely', () {
    final legacy = jsonEncode({
      'plans': [
        {
          'sourcePlanId': 'legacy',
          'title': 'Legacy',
          'weekMode': 'evenOdd',
          'tasks': [
            {
              'sourceTaskId': 'even-old-f',
              'title': 'Even',
              'description': '',
              'hour': 8,
              'minute': 0,
              'repeatDays': [1],
              'enabled': true,
              'weekAssignments': ['f'],
              'alarmId': 101,
            },
            {
              'sourceTaskId': 'odd-old-z',
              'title': 'Odd',
              'description': '',
              'hour': 9,
              'minute': 0,
              'repeatDays': [1],
              'enabled': true,
              'weekAssignments': ['z'],
              'alarmId': 102,
            },
          ],
          'sourceFormat': 'twince-plan',
          'sourceVersion': 1,
        },
      ],
      'weekCycle': {'anchorSaturday': '2026-10-24', 'even': true},
    });
    final migrated = decodePlanLibraryDocument(legacy).plans.single.tasks;
    expect(migrated[0].weekTags, ['Z']);
    expect(migrated[1].weekTags, ['F']);
    expect(migrated[0].weekText, 'Even (Z)');
    expect(migrated[1].weekText, 'Odd (F)');

    final alreadyCurrent = jsonEncode({
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
              'description': '',
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
    });
    expect(
      decodePlanLibraryDocument(alreadyCurrent)
          .plans
          .single
          .tasks
          .single
          .weekTags,
      ['Z'],
    );
  });

  test('Z runs on even weeks and F runs on odd weeks', () {
    expect(recurrenceOf(const ['Z']), PlanRecurrence.even);
    expect(recurrenceOf(const ['even']), PlanRecurrence.even);
    expect(recurrenceOf(const ['F']), PlanRecurrence.odd);
    expect(recurrenceOf(const ['odd']), PlanRecurrence.odd);
    expect(recurrenceOf(const ['both']), PlanRecurrence.both);
    expect(recurrenceOf(const ['nope']), isNull);

    final cycle = WeekCycle(anchorSaturday: DateTime(2026, 10, 24), even: true);
    final from = DateTime(2026, 10, 24, 6);
    final evenWeek = nextLocalAlarm(
      from: from,
      hour: 7,
      minute: 30,
      repeatDays: const [DateTime.monday],
      weekTags: const ['Z'],
      cycle: cycle,
    );
    final oddWeek = nextLocalAlarm(
      from: from,
      hour: 14,
      minute: 0,
      repeatDays: const [DateTime.tuesday],
      weekTags: const ['F'],
      cycle: cycle,
    );
    expect(evenWeek, DateTime(2026, 10, 26, 7, 30));
    expect(isEvenWeek(cycle, evenWeek!), isTrue);
    expect(oddWeek, DateTime(2026, 11, 3, 14));
    expect(isEvenWeek(cycle, oddWeek!), isFalse);

    final afterSaturday = DateTime(2026, 10, 30, 20);
    final nextEven = nextLocalAlarm(
      from: afterSaturday,
      hour: 7,
      minute: 0,
      repeatDays: const [DateTime.monday],
      weekTags: const ['Z'],
      cycle: cycle,
    );
    final nextOdd = nextLocalAlarm(
      from: afterSaturday,
      hour: 14,
      minute: 0,
      repeatDays: const [DateTime.tuesday],
      weekTags: const ['F'],
      cycle: cycle,
    );
    expect(isEvenWeek(cycle, DateTime(2026, 10, 31)), isFalse);
    expect(nextEven, DateTime(2026, 11, 9, 7));
    expect(isEvenWeek(cycle, nextEven!), isTrue);
    expect(nextOdd, DateTime(2026, 11, 3, 14));
    expect(isEvenWeek(cycle, nextOdd!), isFalse);
    expect(
      currentWeekCaption(cycle, DateTime(2026, 10, 26)),
      'Current week: Even (Z)',
    );
    expect(
      currentWeekCaption(cycle, DateTime(2026, 10, 31)),
      'Current week: Odd (F)',
    );
  });
  test('parity choice persists and an edit resets the current week', () async {
    final storage = MemoryPlanStorage();
    final first = PlanRepository(storage: storage, alarms: _MemoryAlarms());
    await first.setCurrentWeek(even: true, now: DateTime(2026, 10, 26, 15));
    expect(first.weekCycle!.anchorSaturday, DateTime(2026, 10, 24));
    expect(first.isEvenWeekOn(DateTime(2026, 10, 30)), isTrue);

    final reloaded = PlanRepository(storage: storage, alarms: _MemoryAlarms());
    await reloaded.load();
    expect(reloaded.weekConfigured, isTrue);
    expect(reloaded.isEvenWeekOn(DateTime(2026, 10, 28)), isTrue);

    await reloaded.setCurrentWeek(even: false, now: DateTime(2026, 10, 28, 9));
    final edited = PlanRepository(storage: storage, alarms: _MemoryAlarms());
    await edited.load();
    expect(edited.weekCycle!.anchorSaturday, DateTime(2026, 10, 24));
    expect(edited.isEvenWeekOn(DateTime(2026, 10, 26)), isFalse);
  });

  test(
    'only the matching parity is due this week and one-off alarms stay put',
    () {
      final cycle = WeekCycle(
        anchorSaturday: DateTime(2026, 10, 24),
        even: true,
      );
      final from = DateTime(2026, 10, 24, 6);
      final even = nextLocalAlarm(
        from: from,
        hour: 7,
        minute: 30,
        repeatDays: const [DateTime.monday],
        weekTags: const ['Z'],
        cycle: cycle,
      );
      expect(even, DateTime(2026, 10, 26, 7, 30));
      expect(isEvenWeek(cycle, even!), isTrue);

      final odd = nextLocalAlarm(
        from: from,
        hour: 14,
        minute: 0,
        repeatDays: const [DateTime.tuesday],
        weekTags: const ['F'],
        cycle: cycle,
      );
      expect(odd, DateTime(2026, 11, 3, 14, 0));
      expect(isEvenWeek(cycle, odd!), isFalse);

      final both = nextLocalAlarm(
        from: from,
        hour: 18,
        minute: 15,
        repeatDays: const [DateTime.wednesday],
        weekTags: const ['both'],
        cycle: cycle,
      );
      expect(both, DateTime(2026, 10, 28, 18, 15));
      expect(
        nextLocalAlarm(
          from: from,
          hour: 9,
          minute: 0,
          repeatDays: const [DateTime.monday],
          weekTags: const ['nope'],
          cycle: cycle,
        ),
        isNull,
      );
      expect(recurrenceOf(const ['nope']), isNull);
      expect(recurrenceEligible(PlanRecurrence.both, true), isTrue);
      expect(recurrenceEligible(PlanRecurrence.odd, true), isFalse);

      final oneOff = nextLocalAlarm(
        from: DateTime(2026, 10, 26, 8),
        hour: 8,
        minute: 0,
        repeatDays: const [],
        weekTags: const [],
      );
      expect(oneOff, DateTime(2026, 10, 27, 8));
    },
  );

  test(
    'F and Z future occurrences use each occurrence week across Saturday',
    () {
      final cycle = WeekCycle(
        anchorSaturday: DateTime(2026, 10, 24),
        even: true,
      );
      final fridayNight = DateTime(2026, 10, 30, 20);
      final z = nextLocalAlarm(
        from: fridayNight,
        hour: 7,
        minute: 0,
        repeatDays: const [DateTime.monday],
        weekTags: const ['Z'],
        cycle: cycle,
      );
      final f = nextLocalAlarm(
        from: fridayNight,
        hour: 14,
        minute: 0,
        repeatDays: const [DateTime.tuesday],
        weekTags: const ['F'],
        cycle: cycle,
      );
      expect(z, DateTime(2026, 11, 9, 7));
      expect(isEvenWeek(cycle, z!), isTrue);
      expect(f, DateTime(2026, 11, 3, 14));
      expect(isEvenWeek(cycle, f!), isFalse);
    },
  );
  test('valid plan maps endTime and Z/F without using the start time', () {
    final plan = parseTwincePlan(_sample());
    expect(plan.title, 'تمرین');
    expect(plan.weekMode, PlanWeekMode.evenOdd);
    final morning = plan.tasks.firstWhere((task) => task.sourceTaskId == 'z1');
    expect(morning.title, 'تمرین صبح');
    expect(morning.description, 'توضیح');
    expect(morning.hour, 7);
    expect(morning.minute, 30);
    expect(morning.repeatDays, [1]);
    expect(morning.weekAssignments, [PlanWeek.z]);
    expect(morning.weekTags, ['Z']);
    final lab = plan.tasks.firstWhere((task) => task.sourceTaskId == 'f1');
    expect(lab.weekAssignments, [PlanWeek.f]);
    expect(lab.weekTags, ['F']);
    expect(lab.repeatDays, [2, 4]);
    final both = plan.tasks.firstWhere((task) => task.sourceTaskId == 'both');
    expect(both.weekAssignments, [PlanWeek.z, PlanWeek.f]);
    expect(both.weekTags, ['both']);
    expect(both.hour, 18);
    expect(
      plan.tasks.where((task) => task.sourceTaskId == 'both'),
      hasLength(1),
    );
  });

  test('every-week plans are not forced into Z or F', () {
    final raw = _plan(
      mode: 'every',
      tasks: [
        {
          'id': 'e1',
          'title': 'Daily',
          'endTime': '09:00',
          'days': ['sat'],
        },
      ],
    );
    final plan = parseTwincePlan(raw);
    expect(plan.weekMode, PlanWeekMode.every);
    expect(plan.tasks.single.weekAssignments, isEmpty);
    expect(plan.tasks.single.weekText, 'Every week');
    expect(plan.tasks.single.weekTags, ['both']);
  });

  test('malformed documents are rejected', () {
    expect(() => parseTwincePlan('{'), throwsA(isA<PlanImportException>()));
    expect(
      () => parseTwincePlan('[]'),
      throwsA(predicate((error) => '$error'.contains('Invalid JSON'))),
    );
    expect(
      () => parseTwincePlan('{"format":"other","version":1,"plan":{}}'),
      throwsA(
        predicate(
          (error) => '$error'.contains('Unsupported Twince Plan format'),
        ),
      ),
    );
    expect(
      () => parseTwincePlan(
        '{"format":"twince-plan","version":2,"plan":{"id":"p","title":"t","weekMode":"every","tasks":[]}}',
      ),
      throwsA(
        predicate((error) => '$error'.contains('Unsupported Plan version')),
      ),
    );
    expect(
      () => parseTwincePlan(
        '{"format":"twince-plan","version":1,"plan":{"id":"","title":"t","weekMode":"every","tasks":[]}}',
      ),
      throwsA(predicate((error) => '$error'.contains('Missing Plan ID'))),
    );
    expect(
      () => parseTwincePlan(
        _plan(
          tasks: [
            {
              'id': '',
              'title': 'X',
              'endTime': '10:00',
              'days': ['mon'],
              'weekType': 'odd',
              'weekLabel': 'Z',
            },
          ],
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('Missing task ID'))),
    );
    expect(
      () => parseTwincePlan(
        _plan(
          tasks: [
            {
              'id': 'a',
              'title': '  ',
              'endTime': '10:00',
              'days': ['mon'],
              'weekType': 'odd',
              'weekLabel': 'Z',
            },
          ],
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('Task has no title'))),
    );
    expect(
      () => parseTwincePlan(
        _plan(
          tasks: [
            {
              'id': 'a',
              'title': 'X',
              'endTime': '24:00',
              'days': ['mon'],
              'weekType': 'odd',
              'weekLabel': 'Z',
            },
          ],
        ),
      ),
      throwsA(
        predicate((error) => '$error'.contains('Task has no valid end time')),
      ),
    );
    expect(
      () => parseTwincePlan(
        _plan(
          tasks: [
            {
              'id': 'a',
              'title': 'X',
              'endTime': '10:00',
              'days': ['monday'],
              'weekType': 'odd',
              'weekLabel': 'Z',
            },
          ],
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('Invalid weekday'))),
    );
    expect(
      () => parseTwincePlan(
        _plan(
          tasks: [
            {
              'id': 'a',
              'title': 'X',
              'endTime': '10:00',
              'days': ['mon'],
              'weekType': 'odd',
              'weekLabel': 'Z',
            },
          ],
        ),
      ),
      throwsA(
        predicate((error) => '$error'.contains('Invalid Z/F week assignment')),
      ),
    );
  });

  test(
    'import is idempotent, updates in place, and leaves other alarms alone',
    () async {
      final storage = MemoryPlanStorage();
      final alarms = _MemoryAlarms()..saved[1] = _manual();
      final repository = PlanRepository(storage: storage, alarms: alarms);
      final first = repository.preview(_sample());
      expect(first.created, 3);
      await repository.commit(first);
      expect(alarms.saved.length, 4);
      final morning = alarms.saved.values.firstWhere(
        (alarm) => alarm.label == 'تمرین صبح',
      );
      expect(morning.hour, 7);
      expect(morning.minute, 30);
      expect(morning.weekTags, ['Z']);
      expect(alarms.saved[1]!.label, 'Manual');

      final again = repository.preview(_sample());
      expect(again.created, 0);
      expect(again.updated, 3);
      await repository.commit(again);
      expect(alarms.saved.length, 4);
      expect(alarms.saved[morning.id]!.id, morning.id);

      final changed = _sample()
          .replaceFirst('تمرین صبح', 'تمرین عصر')
          .replaceFirst('07:30', '19:45');
      await repository.commit(repository.preview(changed));
      expect(alarms.saved[morning.id]!.label, 'تمرین عصر');
      expect(alarms.saved[morning.id]!.hour, 19);
      expect(alarms.saved[morning.id]!.minute, 45);
      expect(alarms.saved.length, 4);

      final before = storage.value;
      expect(
        () => repository.preview('{'),
        throwsA(isA<PlanImportException>()),
      );
      expect(storage.value, before);
      expect(alarms.saved[1]!.label, 'Manual');

      await repository.deletePlan('plan-1');
      expect(alarms.saved.keys, [1]);
      expect(repository.plans, isEmpty);
    },
  );

  testWidgets('plan section shows an imported Persian task time', (
    tester,
  ) async {
    final repository = PlanRepository(
      storage: MemoryPlanStorage(),
      alarms: _MemoryAlarms(),
    );
    await repository.commit(repository.preview(_sample()));
    await repository.setCurrentWeek(even: true, now: DateTime(2026, 10, 26));
    await tester.pumpWidget(
      MaterialApp(
        theme: TwinceTheme.dark(),
        home: PlanScreen(repository: repository),
      ),
    );
    await tester.pump();
    expect(find.text('تمرین'), findsOneWidget);
    await tester.tap(find.text('تمرین'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('تمرین صبح'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(find.text('06:00'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final data = widget.data ?? '';
        return data.contains('Even (Z)') &&
            data.contains('This week') &&
            !data.contains('Not this week');
      }),
      findsWidgets,
    );
    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final data = widget.data ?? '';
        return data.contains('Odd (F)') && data.contains('Not this week');
      }),
      findsOneWidget,
    );
  });

  testWidgets('opening Plan asks once, and edit saves the other parity', (
    tester,
  ) async {
    final storage = MemoryPlanStorage();
    final alarms = _MemoryAlarms()..saved[1] = _manual();
    final repository = PlanRepository(storage: storage, alarms: alarms);

    Future<void> show({required bool active}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: TwinceTheme.dark(),
          home: PlanScreen(repository: repository, active: active),
        ),
      );
    }

    await show(active: false);
    await tester.pump();
    expect(find.textContaining('Even week (Z)'), findsNothing);

    await show(active: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Current week'), findsOneWidget);
    expect(find.textContaining('Even week (Z)'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final dismissed = await navigator.maybePop();
    await tester.pump();
    expect(dismissed, isTrue);
    expect(find.textContaining('Even week (Z)'), findsOneWidget);

    await tester.tap(find.textContaining('Even week (Z)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current week: Even (Z)'), findsOneWidget);
    expect(find.textContaining('Even week (Z)'), findsNothing);

    await show(active: false);
    await tester.pump();
    await show(active: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Even week (Z)'), findsNothing);
    expect(find.textContaining('Current week: Even (Z)'), findsOneWidget);

    final saved = PlanRepository(storage: storage, alarms: _MemoryAlarms());
    await saved.load();
    expect(saved.weekCycle!.even, isTrue);
    expect(saved.weekCycle!.anchorSaturday, saturdayOnOrBefore(DateTime.now()));

    await repository.commit(repository.preview(_sample()));
    final before = alarms.upserts.length;
    expect(alarms.saved[1]!.label, 'Manual');

    await tester.tap(find.byTooltip('Edit current week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Odd week (F)'), findsOneWidget);
    await tester.tap(find.textContaining('Odd week (F)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Current week: Odd (F)'), findsOneWidget);
    final edited = PlanRepository(storage: storage, alarms: _MemoryAlarms());
    await edited.load();
    expect(edited.weekCycle!.even, isFalse);
    expect(
      edited.weekCycle!.anchorSaturday,
      saturdayOnOrBefore(DateTime.now()),
    );
    expect(alarms.upserts.length, before + 3);
    expect(alarms.upserts.skip(before), isNot(contains(1)));
    expect(alarms.saved[1]!.label, 'Manual');
    expect(alarms.saved.length, 4);
  });
}

AlarmItem _manual() {
  return const AlarmItem(
    id: 1,
    hour: 8,
    minute: 0,
    label: 'Manual',
    subtitle: 'Time to start your task',
    enabled: true,
    vibrate: true,
    soundUri: '',
    repeatDays: [1],
  );
}
