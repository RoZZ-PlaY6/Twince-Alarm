import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/screens/edit_alarm_screen.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

const _channel = MethodChannel('com.twince.alarm/alarms');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> previews;
  late int stops;
  late List<String> methods;

  setUp(() {
    previews = [];
    stops = 0;
    methods = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'listAlarmSounds':
            return [
              {'name': 'Default alarm', 'uri': ''},
              {'name': 'Beep', 'uri': 'content://beep'},
            ];
          case 'previewSound':
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            previews.add(args['uri'] as String? ?? '');
            return true;
          case 'stopPreview':
            stops += 1;
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    );
  });

  Future<void> openPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TwinceTheme.dark(),
        home: const EditAlarmScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('Sound'));
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
  }

  testWidgets('selecting a sound previews it and leaves the picker open', (tester) async {
    await openPicker(tester);

    expect(find.text('Alarm sound'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Beep'), findsOneWidget);

    await tester.tap(find.text('Beep'));
    await tester.pump();

    expect(previews, ['content://beep']);
    expect(find.text('Alarm sound'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.tap(find.text('Default alarm'));
    await tester.pump();
    await tester.tap(find.text('Beep'));
    await tester.pump();

    expect(previews, ['content://beep', '', 'content://beep']);
    expect(find.text('Alarm sound'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Alarm sound'), findsNothing);
    expect(find.text('Add alarm'), findsOneWidget);
    expect(find.text('Beep'), findsOneWidget);
    expect(find.text('Save alarm'), findsOneWidget);
    expect(stops, greaterThan(0));
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a preview error keeps the picker open', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'listAlarmSounds':
            return [
              {'name': 'Default alarm', 'uri': ''},
              {'name': 'Beep', 'uri': 'content://beep'},
            ];
          case 'previewSound':
            throw PlatformException(code: 'preview', message: 'busy');
          case 'stopPreview':
            stops += 1;
            return true;
          default:
            return null;
        }
      },
    );

    await openPicker(tester);
    await tester.tap(find.text('Beep'));
    await tester.pump();

    expect(find.text('Alarm sound'), findsOneWidget);
    expect(find.text('Could not play that sound'), findsOneWidget);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
