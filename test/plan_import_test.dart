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
      'weekReference': {'evenLabel': 'F', 'oddLabel': 'Z'},
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
        'weekType': 'odd',
        'weekLabel': 'Z',
      },
      {
        'id': 'f1',
        'title': 'Lab',
        'endTime': '14:00',
        'days': ['tue', 'thu'],
        'weekType': 'even',
        'weekLabel': 'F',
      },
      {
        'id': 'both',
        'title': 'Studio',
        'endTime': '18:15',
        'days': ['wed'],
        'weekType': 'odd',
        'weekLabel': 'Z',
      },
      {
        'id': 'both',
        'title': 'Studio',
        'endTime': '18:15',
        'days': ['wed'],
        'weekType': 'even',
        'weekLabel': 'F',
      },
    ],
  );
}

void main() {
  test('ISO odd weeks are Z and even weeks are F', () {
    final date = DateTime(2026, 10, 26);
    expect(planWeekLabel(date), isoWeekNumber(date).isOdd ? 'Z' : 'F');
    expect(planWeekMatches(date, const ['Z', 'F']), isTrue);
    expect(planWeekMatches(date, const []), isTrue);
    expect(planWeekMatches(date, [planWeekLabel(date)]), isTrue);
    expect(
      planWeekMatches(date, [planWeekLabel(date) == 'Z' ? 'F' : 'Z']),
      isFalse,
    );
  });

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
    expect(both.weekTags, isEmpty);
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
    expect(plan.tasks.single.weekTags, isEmpty);
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
              'weekLabel': 'F',
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
    expect(find.textContaining('Z'), findsWidgets);
    expect(find.text('06:00'), findsNothing);
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
