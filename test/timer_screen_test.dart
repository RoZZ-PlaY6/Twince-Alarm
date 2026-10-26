import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/main.dart';

const _channel = MethodChannel('com.twince.alarm/alarms');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> previews;
  late int stops;

  setUp(() {
    previews = [];
    stops = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        switch (call.method) {
          case 'listAlarmSounds':
            return [
              {'name': 'Default alarm', 'uri': ''},
              {'name': 'Beep', 'uri': 'content://beep'},
            ];
          case 'previewSound':
            final args = Map<Object?, Object?>.from(call.arguments as Map);
            previews.add('${args['uri']}:${args['loop']}');
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

  Future<void> openTimer(
    WidgetTester tester, {
    Size size = const Size(480, 1100),
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(const TwinceAlarmApp(connectPlatform: false));
    await tester.pump();
    expect(find.text('Alarms'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pump();
  }

  testWidgets('timer is a separate section and quick durations update the display', (tester) async {
    await openTimer(tester);
    expect(find.text('00:00:00'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Pause'), findsNothing);

    await tester.tap(find.text('00:10:00'));
    await tester.pump();
    expect(find.text('00:10:00'), findsWidgets);
    await tester.tap(find.text('00:30:00'));
    await tester.pump();
    expect(find.text('00:30:00'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a one second timer counts down to the completion screen', (tester) async {
    await openTimer(tester);
    await tester.tap(find.byTooltip('Add second'));
    await tester.pump();
    expect(find.text('00:00:01'), findsWidgets);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00:01'), findsWidgets);
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('00:00:00'), findsWidgets);
    expect(find.text('Time is up'), findsOneWidget);
    expect(find.text('07:30'), findsNothing);
    expect(previews, contains(':true'));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Time is up'), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    expect(stops, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('timer sound selection stays open and does not start the timer', (tester) async {
    await openTimer(tester);
    await tester.ensureVisible(find.text('Sound'));
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();

    expect(find.text('Timer sound'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.text('Beep'));
    await tester.pump();
    expect(find.text('Timer sound'), findsOneWidget);
    expect(previews, ['content://beep:false']);
    expect(find.text('Pause'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Timer sound'), findsNothing);
    expect(find.text('Beep'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(stops, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('timer setup fits a short phone', (tester) async {
    await openTimer(tester, size: const Size(360, 640), bottomInset: 48);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('00:10:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
