import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
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
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
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

  testWidgets(
    'timer is a separate section and quick durations update the display',
    (tester) async {
      await openTimer(tester);
      expect(find.byKey(const ValueKey('wheel-seconds')), findsOneWidget);

      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Pause'), findsNothing);

      await tester.tap(find.text('00:10:00'));
      await tester.pump();
      expect(
        (tester
                    .widget<ListWheelScrollView>(
                      find.byKey(const ValueKey('wheel-minutes')),
                    )
                    .controller!
                as FixedExtentScrollController)
            .selectedItem,
        10,
      );
      await tester.tap(find.text('00:30:00'));
      await tester.pump();
      expect(
        (tester
                    .widget<ListWheelScrollView>(
                      find.byKey(const ValueKey('wheel-minutes')),
                    )
                    .controller!
                as FixedExtentScrollController)
            .selectedItem,
        30,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('a one second timer counts down to the completion screen', (
    tester,
  ) async {
    await openTimer(tester);
    await tester.tap(find.byKey(const ValueKey('seconds-1')));
    await tester.pumpAndSettle();
    expect(
      (tester
                  .widget<ListWheelScrollView>(
                    find.byKey(const ValueKey('wheel-seconds')),
                  )
                  .controller!
              as FixedExtentScrollController)
          .selectedItem,
      1,
    );

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

  testWidgets(
    'wheels scroll independently, snap, support mouse and respect bounds',
    (tester) async {
      await openTimer(tester, size: const Size(360, 740));
      FixedExtentScrollController controller(String unit) =>
          tester
                  .widget<ListWheelScrollView>(
                    find.byKey(ValueKey('wheel-$unit')),
                  )
                  .controller!
              as FixedExtentScrollController;
      await tester.tap(find.text('00:10:00'));
      await tester.pump();
      expect(controller('minutes').selectedItem, 10);
      await tester.drag(
        find.byKey(const ValueKey('wheel-minutes')),
        const Offset(0, -75),
      );
      await tester.pumpAndSettle();
      expect(controller('minutes').selectedItem, greaterThan(10));
      expect(
        controller('minutes').offset,
        closeTo(controller('minutes').selectedItem * 50, 0.01),
      );
      expect(controller('hours').selectedItem, 0);
      expect(controller('seconds').selectedItem, 0);
      final oldMinutes = controller('minutes').selectedItem;
      await tester.fling(
        find.byKey(const ValueKey('wheel-minutes')),
        const Offset(0, 100),
        700,
      );
      await tester.pumpAndSettle();
      expect(controller('minutes').selectedItem, lessThan(oldMinutes));
      expect(
        controller('minutes').offset,
        closeTo(controller('minutes').selectedItem * 50, 0.01),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('wheel-seconds'))),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(
            find.byKey(const ValueKey('wheel-seconds')),
          ),
          scrollDelta: const Offset(0, 110),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller('seconds').selectedItem, greaterThan(0));
      expect(
        controller('seconds').offset,
        closeTo(controller('seconds').selectedItem * 50, 0.01),
      );
      await mouse.removePointer();
      controller('hours').jumpToItem(23);
      controller('minutes').jumpToItem(59);
      controller('seconds').jumpToItem(9);
      await tester.pump();
      expect(find.byKey(const ValueKey('seconds-9')), findsOneWidget);
      expect(find.text('09'), findsWidgets);
      await tester.fling(
        find.byKey(const ValueKey('wheel-hours')),
        const Offset(0, -150),
        1000,
      );
      await tester.pumpAndSettle();
      expect(controller('hours').selectedItem, 23);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('23:59:09'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(controller('hours').selectedItem, 23);
    },
  );

  testWidgets(
    'one mouse notch moves one value in both directions for each wheel',
    (tester) async {
      await openTimer(tester);
      FixedExtentScrollController wheel(String unit) =>
          tester
                  .widget<ListWheelScrollView>(
                    find.byKey(ValueKey('wheel-$unit')),
                  )
                  .controller!
              as FixedExtentScrollController;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(0, 0));
      for (final unit in ['hours', 'minutes', 'seconds']) {
        final position = tester.getCenter(find.byKey(ValueKey('wheel-$unit')));
        await mouse.moveTo(position);
        for (final delta in [120.0, 120.0, -120.0, -120.0, -120.0]) {
          final before = wheel(unit).selectedItem;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: position,
              kind: PointerDeviceKind.mouse,
              scrollDelta: Offset(0, delta),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            wheel(unit).selectedItem,
            (before + (delta > 0 ? 1 : -1)).clamp(0, 59),
          );
          expect(
            wheel(unit).offset,
            closeTo(wheel(unit).selectedItem * 50, 0.01),
          );
        }
      }
      await mouse.removePointer();
    },
  );

  testWidgets('trackpad and touch drags remain continuous on each wheel', (
    tester,
  ) async {
    await openTimer(tester);
    for (final unit in ['hours', 'minutes', 'seconds']) {
      final finder = find.byKey(ValueKey('wheel-$unit'));
      final wheel =
          tester.widget<ListWheelScrollView>(finder).controller!
              as FixedExtentScrollController;
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(tester.getCenter(finder));
      await trackpad.panZoomUpdate(
        tester.getCenter(finder),
        pan: const Offset(0, -20),
      );
      await tester.pump();
      expect(wheel.offset, greaterThan(0));
      expect(wheel.offset, lessThan(50));
      await trackpad.panZoomUpdate(
        tester.getCenter(finder),
        pan: const Offset(0, -40),
      );
      await tester.pump();
      expect(wheel.offset, greaterThan(20));
      await trackpad.panZoomEnd();
      await tester.pumpAndSettle();
      expect(wheel.offset, closeTo(wheel.selectedItem * 50, 0.01));
      final start = wheel.offset;
      final drag = await tester.startGesture(tester.getCenter(finder));
      await drag.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 100));
      expect(wheel.offset, greaterThan(start));
      expect(wheel.offset, lessThan(start + 50));
      await drag.up();
      await tester.pumpAndSettle();
      expect(wheel.offset, closeTo(wheel.selectedItem * 50, 0.01));
      final beforeFling = wheel.selectedItem;
      await tester.fling(finder, const Offset(0, -100), 800);
      await tester.pumpAndSettle();
      expect(wheel.selectedItem, greaterThan(beforeFling));
      expect(wheel.offset, closeTo(wheel.selectedItem * 50, 0.01));
    }
  });

  testWidgets('wheels accept keyboard and fit a narrow landscape viewport', (
    tester,
  ) async {
    await openTimer(tester, size: const Size(640, 360));
    await tester.ensureVisible(find.byKey(const ValueKey('wheel-seconds')));
    final context = tester.element(find.byKey(const ValueKey('wheel-seconds')));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final wheel = tester.widget<ListWheelScrollView>(
      find.byKey(const ValueKey('wheel-seconds')),
    );
    expect((wheel.controller! as FixedExtentScrollController).selectedItem, 1);
    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('00:00:01'), findsOneWidget);
  });

  testWidgets('timer sound selection stays open and does not start the timer', (
    tester,
  ) async {
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
    expect(find.byKey(const ValueKey('wheel-seconds')), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('00:10:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
