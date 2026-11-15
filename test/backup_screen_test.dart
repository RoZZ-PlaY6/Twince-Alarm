import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/screens/backup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backup = MethodChannel('com.twince.alarm/backup');
  const alarms = MethodChannel('com.twince.alarm/alarms');
  final valid = jsonEncode({
    'app': 'com.twince.alarm',
    'schemaVersion': 1,
    'createdAt': '2026-11-12T00:00:00Z',
    'alarms': [],
    'sounds': {'last': null, 'favorites': []},
    'planLibrary': {'weekParityMapping': 2, 'plans': []},
  });
  testWidgets('cancelled confirmation and invalid file do not restore', (
    tester,
  ) async {
    var selected = valid;
    var restores = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(backup, (call) async {
      if (call.method == 'choose') return selected;
      if (call.method == 'restore') restores++;
      return null;
    });
    messenger.setMockMethodCallHandler(alarms, (_) async => []);
    addTearDown(() {
      messenger.setMockMethodCallHandler(backup, null);
      messenger.setMockMethodCallHandler(alarms, null);
    });
    await tester.pumpWidget(MaterialApp(home: const BackupScreen()));
    await tester.pump();
    await tester.ensureVisible(find.text('Import backup'));
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    expect(find.text('Replace current data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(restores, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    selected = '{';
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    expect(restores, 0);
    expect(find.textContaining('not valid JSON'), findsOneWidget);
  });
  testWidgets('import, fresh save, rename, cancellation and Save As', (
    tester,
  ) async {
    String? name;
    String label = 'Changed after import';
    Map? written;
    var writable = true;
    var renameSupported = true;
    var saveCancelled = false;
    var restoreCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarms, (call) async {
      switch (call.method) {
        case 'listAlarmSounds':
          return [
            {'name': 'Default alarm', 'uri': ''},
          ];
        case 'getAlarms':
          return [
            {
              'id': 3,
              'hour': 7,
              'minute': 0,
              'label': label,
              'subtitle': 'Test',
              'enabled': true,
              'vibrate': true,
              'soundUri': '',
              'repeatDays': <int>[],
              'weekTags': <String>[],
            },
          ];
        case 'loadPlanLibrary':
          return '';
        case 'loadLastAlarmSound':
          return '';
        case 'loadFavoriteAlarmSounds':
          return <String>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(backup, (call) async {
      switch (call.method) {
        case 'current':
          return name == null ? null : {'name': name};
        case 'choose':
          return valid;
        case 'restore':
          restoreCalls++;
          return {
            'exactAlarm': true,
            'notifications': true,
            'fullScreenIntent': true,
          };
        case 'useSelected':
          name = 'TWINCEALARM_imported.json';
          return null;
        case 'saveCurrent':
          if (!writable) return false;
          written =
              jsonDecode((call.arguments as Map)['content'] as String) as Map;
          return true;
        case 'rename':
          if (!renameSupported) return false;
          name = (call.arguments as Map)['name'] as String;
          return true;
        case 'save':
          if (saveCancelled) return false;
          name = (call.arguments as Map)['name'] as String;
          written =
              jsonDecode((call.arguments as Map)['content'] as String) as Map;
          return true;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(backup, null);
      messenger.setMockMethodCallHandler(alarms, null);
    });
    await tester.pumpWidget(const MaterialApp(home: BackupScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Current backup: None selected'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Import backup')).dy,
      lessThan(tester.getTopLeft(find.text('Save to current backup')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Save to current backup')).dy,
      lessThan(tester.getTopLeft(find.text('Create new backup')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Create new backup')).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('current-backup'))).dy),
    );
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restoreCalls, 1);
    expect(
      find.text('Current backup: TWINCEALARM_imported.json'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save to current backup'));
    await tester.pumpAndSettle();
    expect((written!['alarms'] as List).single['label'], label);
    await tester.tap(find.text('Rename backup file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'TWINCEALARM_renamed.json');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Current backup: TWINCEALARM_renamed.json'),
      findsOneWidget,
    );
    writable = false;
    await tester.tap(find.text('Save to current backup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('In-place saving is unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(name, 'TWINCEALARM_renamed.json');
    renameSupported = false;
    await tester.tap(find.text('Rename backup file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'TWINCEALARM_copy.json');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('original file will remain'), findsOneWidget);
    await tester.tap(find.text('Save as'));
    await tester.pumpAndSettle();
    expect(name, 'TWINCEALARM_copy.json');
    saveCancelled = true;
    await tester.tap(find.text('Create new backup'));
    await tester.pumpAndSettle();
    expect(name, 'TWINCEALARM_copy.json');
    saveCancelled = false;
    await tester.tap(find.text('Create new backup'));
    await tester.pumpAndSettle();
    expect(name, startsWith('TWINCEALARM_'));
    expect(name, endsWith('.json'));
    expect(name, isNot('TWINCEALARM_copy.json'));
  });
}
