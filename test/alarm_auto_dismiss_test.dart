import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/screens/ringing_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.twince.alarm/alarms');
  const events = 'com.twince.alarm/events';

  testWidgets('only the matching auto-dismiss closes the lock-screen preview', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async => call.method == 'previewRing' ? 42 : null);
    messenger.setMockMethodCallHandler(const MethodChannel(events), (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(const MethodChannel(events), null);
    });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RingingScreen(
        hour: 7, minute: 30, title: 'Preview alarm', subtitle: 'Test', preview: true,
      ))),
      child: const Text('Open'),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Test on lock screen'));
    await tester.pump();
    Future<void> send(int token) async {
      await messenger.handlePlatformMessage(events, const StandardMethodCodec().encodeSuccessEnvelope({
        'type': 'dismiss', 'alarmId': 0, 'snoozeMinutes': 0, 'label': '',
        'token': token, 'automatic': true, 'preview': true,
      }), (_) {});
      await tester.pump();
    }
    await send(41);
    expect(find.text('Preview alarm'), findsOneWidget);
    await send(42);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Preview alarm'), findsNothing);
  });
}


