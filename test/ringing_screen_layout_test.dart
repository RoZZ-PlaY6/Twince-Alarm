import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/screens/ringing_screen.dart';
import 'package:twince_alarm/theme/twince_theme.dart';
import 'package:twince_alarm/widgets/neon_bell.dart';

Future<void> _pumpPreview(
  WidgetTester tester, {
  required Size size,
  double topInset = 0,
  double bottomInset = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: topInset, bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset, bottom: bottomInset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  await tester.pumpWidget(
    MaterialApp(
      theme: TwinceTheme.dark(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RingingScreen(
        hour: 7,
        minute: 30,
        title: 'Morning workout',
        subtitle: 'Time to start your task',
        preview: true,
      ),
    ),
  );
  await tester.pump();
}

void _expectSampleContent() {
  expect(find.text('07:30'), findsOneWidget);
  expect(find.text('Morning workout'), findsOneWidget);
  expect(find.text('Time to start your task'), findsOneWidget);
  expect(find.text('Snooze 5min'), findsOneWidget);
  expect(find.text('Snooze 10min'), findsOneWidget);
}

void _expectSnoozeVisible(WidgetTester tester) {
  final viewHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final bottomLimit = viewHeight - tester.view.padding.bottom;
  for (final label in ['Snooze 5min', 'Snooze 10min']) {
    final rect = tester.getRect(find.widgetWithText(SnoozePill, label));
    expect(rect.top, greaterThanOrEqualTo(tester.view.padding.top));
    expect(rect.bottom, lessThanOrEqualTo(bottomLimit));
    expect(rect.height, greaterThanOrEqualTo(48));
  }
}

void main() {
  testWidgets('preview fits a tall phone without scrolling the sample alarm', (tester) async {
    await _pumpPreview(tester, size: const Size(480, 900));
    _expectSampleContent();
    _expectSnoozeVisible(tester);
    expect(find.text('Test on lock screen'), findsOneWidget);

    await tester.tap(find.text('Snooze 5min'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('preview keeps both snooze buttons visible on a short phone', (tester) async {
    await _pumpPreview(
      tester,
      size: const Size(480, 640),
      topInset: 24,
      bottomInset: 48,
    );
    _expectSampleContent();
    _expectSnoozeVisible(tester);
    expect(find.text('Test on lock screen'), findsOneWidget);

    await tester.tap(find.text('Snooze 10min'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('preview keeps snooze buttons visible with a navigation bar', (tester) async {
    await _pumpPreview(
      tester,
      size: const Size(480, 700),
      topInset: 32,
      bottomInset: 48,
    );
    _expectSampleContent();
    _expectSnoozeVisible(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
