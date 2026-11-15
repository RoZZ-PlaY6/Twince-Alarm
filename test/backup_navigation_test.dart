import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/screens/home_screen.dart';

void main() {
  testWidgets('hover and keyboard focus reveal tooltips below icon buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(connectPlatform: false)),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(0, 400));
    for (final label in ['Backup', 'Preview alarm screen']) {
      final button = find.byTooltip(label);
      expect(find.text(label), findsNothing);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(label), findsOneWidget);
      final tooltip = tester.getRect(find.text(label));
      expect(tooltip.top, greaterThan(tester.getRect(button).bottom));
      expect(tooltip.left, greaterThanOrEqualTo(0));
      expect(tooltip.right, lessThanOrEqualTo(320));
      await mouse.moveTo(const Offset(0, 400));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Backup'), findsOneWidget);
  });

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'backup is left of preview and opens a dedicated view at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          const MaterialApp(home: HomeScreen(connectPlatform: false)),
        );
        await tester.pump();
        final backup = find.byTooltip('Backup');
        expect(find.text('Backup'), findsNothing);
        final preview = find.byTooltip('Preview alarm screen');
        expect(backup, findsOneWidget);
        expect(
          find.descendant(of: backup, matching: find.byIcon(Icons.history)),
          findsOneWidget,
        );
        expect(
          tester.getRect(backup).right,
          lessThanOrEqualTo(tester.getRect(preview).left),
        );
        expect(tester.getRect(preview).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await tester.tap(backup);
        await tester.pumpAndSettle();
        expect(find.text('Create new backup'), findsOneWidget);
        expect(find.text('Import backup'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Preview alarm screen'), findsOneWidget);
      },
    );
  }
}
