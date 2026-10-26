import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/main.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';

AlarmItem _draft({int id = 0, String label = 'Morning workout', List<int> days = const [1, 2, 3, 4, 5]}) {
  return AlarmItem(
    id: id,
    hour: 7,
    minute: 30,
    label: label,
    subtitle: 'Time to start your task',
    enabled: true,
    vibrate: true,
    soundUri: '',
    repeatDays: days,
    scheduleError: 'should be cleared',
  );
}

void main() {
  test('memory session saves, updates, and lists alarms without scheduling', () async {
    final bridge = AlarmBridge.memory();
    final created = await bridge.upsert(_draft());
    expect(created.id, 1);
    expect(created.scheduleError, isEmpty);
    expect(created.label, 'Morning workout');

    final updated = await bridge.upsert(_draft(id: created.id, label: 'Evening'));
    expect(updated.id, created.id);
    expect(updated.label, 'Evening');

    final second = await bridge.upsert(_draft(label: 'Noon'));
    expect(second.id, isNot(created.id));

    final alarms = await bridge.getAlarms();
    expect(alarms.map((alarm) => alarm.label), ['Evening', 'Noon']);
    expect(alarms.every((alarm) => alarm.scheduleError.isEmpty), isTrue);

    final disabled = await bridge.setEnabled(created.id, false);
    expect(disabled.enabled, isFalse);
    expect((await bridge.getAlarms()).firstWhere((alarm) => alarm.id == created.id).enabled, isFalse);

    await bridge.delete(second.id);
    expect((await bridge.getAlarms()).map((alarm) => alarm.id), [created.id]);
  });

  test('a new memory bridge does not keep the previous session', () async {
    final first = AlarmBridge.memory();
    await first.upsert(_draft());
    final second = AlarmBridge.memory();
    expect(await second.getAlarms(), isEmpty);
  });

  test('memory session does not call Android-only alarm APIs', () async {
    final bridge = AlarmBridge.memory();
    expect(await bridge.events.isEmpty, isTrue);
    expect(await bridge.permissions(), AlarmPermissions.granted);
    expect(await bridge.listSounds(), hasLength(1));
    expect(await bridge.consumeEvents(), isEmpty);
    expect(await bridge.consumeClockIntent(), isNull);
    expect(await bridge.requestNotifications(), isTrue);
    await bridge.previewSound('');
    await bridge.stopPreview();
    await bridge.previewRing();
    await bridge.openExactAlarmSettings();
    await bridge.openFullScreenIntentSettings();
    await bridge.rescheduleAll();
  });

  test('missing alarm toggle reports not found', () async {
    final bridge = AlarmBridge.memory();
    expect(bridge.setEnabled(4, false), throwsA(isA<Exception>()));
  });

  testWidgets('alarm form can be saved and shown from the in-memory session', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    AlarmBridge.instance.useMemorySession();
    addTearDown(AlarmBridge.instance.clearMemorySession);

    await tester.pumpWidget(const TwinceAlarmApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('No alarms yet'), findsOneWidget);
    expect(find.text('Exact alarms are off'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump();

    expect(find.text('Add alarm'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Morning workout');
    await tester.ensureVisible(find.text('Save alarm'));
    await tester.tap(find.text('Save alarm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Could not save the alarm'), findsNothing);
    expect(find.text('No alarms yet'), findsNothing);
    expect(find.text('Morning workout'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
