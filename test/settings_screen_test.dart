import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/main.dart';
import 'package:twince_alarm/models/imported_plan.dart';
import 'package:twince_alarm/screens/app_shell.dart';
import 'package:twince_alarm/services/plan_repository.dart';
import 'package:twince_alarm/services/plan_week.dart';
import 'package:twince_alarm/screens/settings_screen.dart';
import 'package:twince_alarm/services/app_version.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

Future<void> show(
  WidgetTester tester, {
  Future<String> Function()? loadVersion,
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TwinceTheme.dark(),
      home: SettingsScreen(loadVersion: loadVersion ?? () async => '1.0.8'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, (call) async {
          return {
            'appName': 'twince_alarm',
            'packageName': 'twince_alarm',
            'version': '',
            'buildNumber': '1',
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfo, null);
  });

  test('the configured pubspec version is 1.0.8', () async {
    expect(await loadAppVersion(), '1.0.8');
  });

  testWidgets('settings shows the configured version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: TwinceTheme.dark(), home: const SettingsScreen()),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(find.text('Version 1.0.8'), findsOneWidget);
    expect(find.text('Version unavailable'), findsNothing);
    expect(find.text('Version unavailable'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('settings shows the version and copyright', (tester) async {
    await show(tester);
    expect(find.text('Version …'), findsOneWidget);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);

    await tester.pump();
    expect(find.text('Version 1.0.8'), findsOneWidget);
  });

  testWidgets('settings has no week or parity controls', (tester) async {
    await show(tester);
    await tester.pump();
    expect(find.text('Version 1.0.8'), findsOneWidget);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);
    expect(find.textContaining('هفته جاری'), findsNothing);
    expect(find.textContaining('هفته زوج'), findsNothing);
    expect(find.textContaining('هفته فرد'), findsNothing);
    expect(find.text('تغییر'), findsNothing);
    expect(find.text('بازنشانی'), findsNothing);
    expect(find.text('انصراف'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a version failure is shown and disposal is safe', (
    tester,
  ) async {
    final pending = Completer<String>();
    await show(tester, loadVersion: () => pending.future);
    await tester.pump();
    expect(find.text('Version …'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete('9.9.9');
    await tester.pump();

    await show(tester, loadVersion: () async => throw StateError('missing'));
    await tester.pump();
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('settings is the left navigation destination', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TwinceAlarmApp(connectPlatform: false));
    await tester.pump();
    expect(find.text('Alarms'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final settingsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('shell-nav')),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    expect(settingsIcon.color, TwinceColors.cyan);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);
    expect(find.text('Alarms'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('settings card fills a wide web viewport', (tester) async {
    const size = Size(1440, 900);
    await show(tester, size: size);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(const Key('settings-card')));
    expect(rect.width, greaterThan(520));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.center.dx, closeTo(size.width / 2, 16));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.center.dy, closeTo(size.height / 2, size.height * 0.12));
    expect(find.text('Backup'), findsNothing);
    expect(find.text('Create backup'), findsNothing);
    expect(find.text('Import backup'), findsNothing);
    expect(rect.height, greaterThan(280));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Version 1.0.8'), findsOneWidget);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);
  });

  testWidgets('settings card fits a narrow phone', (tester) async {
    const size = Size(320, 480);
    await show(tester, size: size);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byKey(const Key('settings-card')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    expect(rect.width, greaterThan(200));
    expect(rect.width, lessThan(size.width));
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Version 1.0.8'), findsOneWidget);
    expect(find.text('© 2026. All rights reserved.'), findsOneWidget);
  });

  testWidgets('navigation order and selection stay usable', (tester) async {
    Future<void> open(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        TwinceAlarmApp(key: ValueKey(size), connectPlatform: false),
      );
      await tester.pump();
    }

    Finder label(String text) {
      return find.descendant(
        of: find.byKey(const Key('shell-nav')),
        matching: find.text(text),
      );
    }

    void expectOrder() {
      const names = ['Settings', 'Alarm', 'Timer', 'Plan'];
      final centers = [
        for (final name in names) tester.getCenter(label(name)).dx,
      ];
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i], greaterThan(centers[i - 1] + 8));
      }
    }

    void expectSelected(String selected) {
      for (final name in ['Settings', 'Alarm', 'Timer', 'Plan']) {
        final text = tester.widget<Text>(label(name));
        expect(
          text.style?.color,
          name == selected ? TwinceColors.cyan : TwinceColors.muted,
        );
        final dotFinder = find.byKey(ValueKey('nav-dot-$name'));
        final dot = tester.widget<Container>(dotFinder);
        final decoration = dot.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(
          decoration.color,
          name == selected
              ? TwinceColors.cyan
              : TwinceColors.muted.withValues(alpha: 0.4),
        );
        expect(decoration.boxShadow != null, name == selected);
        expect(tester.getSize(dotFinder), const Size(4, 4));
        expect(
          tester.getCenter(dotFinder).dx,
          closeTo(tester.getCenter(label(name)).dx, 0.01),
        );
        expect(
          tester.getTopLeft(dotFinder).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(label(name)).dy),
        );
      }
    }

    for (final size in const [Size(320, 640), Size(1280, 800)]) {
      await open(size);
      expectOrder();
      expectSelected('Alarm');
      expect(find.text('Alarms'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(label('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expectSelected('Settings');
      expect(find.text('© 2026. All rights reserved.'), findsOneWidget);
      expect(find.text('Alarms'), findsNothing);

      await tester.tap(label('Timer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expectSelected('Timer');
      expect(find.byKey(const ValueKey('wheel-seconds')), findsOneWidget);

      await tester.tap(label('Alarm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expectSelected('Alarm');
      expect(find.text('Alarms'), findsOneWidget);

      await tester.tap(label('Plan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expectSelected('Plan');
      expect(find.text('Plans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('navigation animates one pill across every destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = MemoryPlanStorage()
      ..value = encodePlanLibrary(
        [],
        weekCycle: WeekCycle(
          anchorSaturday: DateTime(2026, 11, 14),
          even: true,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        theme: TwinceTheme.dark(),
        home: AppShell(
          connectPlatform: false,
          plans: PlanRepository(storage: storage),
        ),
      ),
    );
    await tester.pump();

    const names = ['Settings', 'Alarm', 'Timer', 'Plan'];
    final nav = find.byKey(const Key('shell-nav'));
    final pill = find.byKey(const Key('shell-nav-pill'));
    Finder label(String name) =>
        find.descendant(of: nav, matching: find.text(name));
    final inks = find.descendant(of: nav, matching: find.byType(InkWell));
    expect(inks, findsNWidgets(4));
    for (final ink in tester.widgetList<InkWell>(inks)) {
      for (final state in [
        WidgetState.hovered,
        WidgetState.focused,
        WidgetState.pressed,
      ]) {
        expect(ink.overlayColor?.resolve({state}), Colors.transparent);
      }
    }
    for (final finder in inks.evaluate()) {
      final size = tester.getSize(find.byWidget(finder.widget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    for (var from = 0; from < names.length; from++) {
      await tester.tap(label(names[from]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      for (var to = 0; to < names.length; to++) {
        if (from == to) continue;
        final start = tester.getCenter(pill).dx;
        final end = tester.getCenter(label(names[to])).dx;
        await tester.tap(label(names[to]));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('shell-nav-pill')), findsOneWidget);
        final middle = tester.getCenter(pill).dx;
        expect(middle, greaterThan(start < end ? start : end));
        expect(middle, lessThan(start > end ? start : end));
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.getCenter(pill).dx, closeTo(end, 0.01));
        for (final name in names) {
          expect(
            tester.widget<Text>(label(name)).style?.color,
            name == names[to] ? TwinceColors.cyan : TwinceColors.muted,
          );
        }
        await tester.tap(label(names[from]));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
      }
    }
    expect(tester.takeException(), isNull);
  });
}
