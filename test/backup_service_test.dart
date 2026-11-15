import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmsChannel = MethodChannel('com.twince.alarm/alarms');
  const backupChannel = MethodChannel('com.twince.alarm/backup');
  final alarm = <String, Object?>{
    'id': 7,
    'hour': 6,
    'minute': 30,
    'label': 'Wake',
    'subtitle': 'Work',
    'enabled': true,
    'vibrate': false,
    'soundUri': 'content://tone/1',
    'repeatDays': [1, 3],
    'weekTags': ['Z'],
  };
  final library = <String, Object?>{
    'weekParityMapping': 2,
    'weekCycle': {'anchorSaturday': '2026-11-07', 'even': true},
    'plans': [
      {
        'sourcePlanId': 'plan1',
        'title': 'Classes',
        'weekMode': 'evenOdd',
        'sourceFormat': 'twince-plan',
        'sourceVersion': 1,
        'exportedAt': '',
        'timezone': '',
        'tasks': [
          {
            'sourceTaskId': 'task1',
            'title': 'Work',
            'description': 'Class',
            'hour': 6,
            'minute': 30,
            'repeatDays': [1, 3],
            'enabled': true,
            'weekAssignments': ['z'],
            'alarmId': 7,
          },
        ],
      },
    ],
  };
  Map<dynamic, dynamic>? restored;
  setUp(() {
    restored = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmsChannel, (call) async {
      switch (call.method) {
        case 'getAlarms':
          return [alarm];
        case 'listAlarmSounds':
          return [
            {'name': 'Default alarm', 'uri': ''},
            {'name': 'Bell', 'uri': 'content://tone/1'},
          ];
        case 'loadPlanLibrary':
          return jsonEncode(library);
        case 'loadLastAlarmSound':
          return 'content://tone/1';
        case 'loadFavoriteAlarmSounds':
          return ['content://tone/1'];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(backupChannel, (call) async {
      if (call.method == 'restore') {
        restored = call.arguments as Map;
        return {'exactAlarm': true, 'notifications': true};
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmsChannel, null);
    messenger.setMockMethodCallHandler(backupChannel, null);
  });

  test('exports and resolves all persisted data without device URIs', () async {
    final service = BackupService();
    final raw = await service.create();
    expect(raw, isNot(contains('content://')));
    final data = BackupService.validate(raw);
    expect(data['planLibrary'], library);
    expect((data['alarms'] as List).single['sound'], 'Bell');
    await service.restore(data);
    expect((restored!['alarms'] as List).single, alarm);
    expect(jsonDecode(restored!['planLibrary'] as String), library);
    expect(restored!['lastSound'], 'content://tone/1');
    expect(restored!['favoriteSounds'], ['content://tone/1']);
  });

  test(
    'rejects corrupt, wrong-app, unsupported and dangling references',
    () async {
      final valid = BackupService.validate(await BackupService().create());
      expect(() => BackupService.validate('{'), throwsFormatException);
      for (final change in [
        {'app': 'com.twince'},
        {'schemaVersion': 2},
        {'alarms': []},
        {'createdAt': 'bad'},
      ]) {
        expect(
          () => BackupService.validate(jsonEncode({...valid, ...change})),
          throwsFormatException,
        );
      }
      expect(restored, isNull);
    },
  );
}
