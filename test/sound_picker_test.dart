import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/screens/edit_alarm_screen.dart';
import 'package:twince_alarm/widgets/sound_picker.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

const _channel = MethodChannel('com.twince.alarm/alarms');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> previews;
  late int stops;
  late List<String> methods;

  late String? remembered;
  late List<String> favorites;

  setUp(() {
    previews = [];
    stops = 0;
    methods = [];
    remembered = null;
    favorites = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          methods.add(call.method);
          switch (call.method) {
            case 'listAlarmSounds':
              return [
                {'name': 'Default alarm', 'uri': ''},
                {'name': 'Beep', 'uri': 'content://beep'},
                {'name': 'Chime', 'uri': 'content://chime'},
                {'name': 'Bell', 'uri': 'content://bell'},
              ];
            case 'loadLastAlarmSound':
              return remembered ?? '';
            case 'saveLastAlarmSound':
              final args = Map<Object?, Object?>.from(call.arguments as Map);
              remembered = args['uri'] as String? ?? '';
              return true;
            case 'loadFavoriteAlarmSounds':
              return favorites;
            case 'saveFavoriteAlarmSounds':
              final args = Map<Object?, Object?>.from(call.arguments as Map);
              final raw = args['uris'];
              favorites = raw is List
                  ? raw.map((item) => item.toString()).toList()
                  : [];
              return true;
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
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> openPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: TwinceTheme.dark(), home: const EditAlarmScreen()),
    );
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('Sound'));
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
  }

  testWidgets('selecting a sound previews it and leaves the picker open', (
    tester,
  ) async {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
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
        });

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

  testWidgets('a new alarm starts with the last selected sound', (
    tester,
  ) async {
    await openPicker(tester);
    await tester.tap(find.text('Beep'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Beep'), findsOneWidget);
    expect(remembered, 'content://beep');
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(theme: TwinceTheme.dark(), home: const EditAlarmScreen()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Beep'), findsOneWidget);
    expect(find.text('Default alarm'), findsNothing);

    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(_checkedTitle(tester), 'Beep');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a missing remembered sound falls back to the default tone', (
    tester,
  ) async {
    remembered = 'content://removed';
    await openPicker(tester);

    expect(find.text('Default alarm'), findsWidgets);
    expect(find.text('Custom tone'), findsNothing);
    expect(_checkedTitle(tester), 'Default alarm');
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('editing an alarm keeps that alarm sound', (tester) async {
    remembered = 'content://beep';
    const existing = AlarmItem(
      id: 7,
      hour: 8,
      minute: 15,
      label: 'School',
      subtitle: 'Time to start your task',
      enabled: true,
      vibrate: true,
      soundUri: 'content://chime',
      repeatDays: [],
    );
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: EditAlarmScreen(alarm: existing)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Chime'), findsOneWidget);
    expect(find.text('Beep'), findsNothing);
    expect(existing.soundUri, 'content://chime');
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(_checkedTitle(tester), 'Chime');
    expect(existing.soundUri, 'content://chime');

    final previewsBefore = previews.length;
    await tester.tap(_favoriteButton(tester, 'Beep', favorite: false));
    await tester.pump();

    expect(existing.soundUri, 'content://chime');
    expect(_checkedTitle(tester), 'Chime');
    expect(previews, hasLength(previewsBefore));
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('favorites keep source order and the last sound is not duplicated', () {
    final sounds = [
      const AlarmSound(name: 'Default alarm', uri: ''),
      const AlarmSound(name: 'Beep', uri: 'content://beep'),
      const AlarmSound(name: 'Chime', uri: 'content://chime'),
      const AlarmSound(name: 'Bell', uri: 'content://bell'),
    ];
    final arranged = arrangeAlarmSounds(
      sounds,
      favoriteUris: const {'content://chime', 'content://beep'},
      pinnedUri: 'content://bell',
    );
    expect(arranged.map((sound) => sound.name), [
      'Beep',
      'Chime',
      'Bell',
      'Default alarm',
    ]);

    final pinnedFavorite = arrangeAlarmSounds(
      sounds,
      favoriteUris: const {'content://bell', 'content://beep'},
      pinnedUri: 'content://bell',
    );
    expect(pinnedFavorite.map((sound) => sound.name), [
      'Beep',
      'Bell',
      'Default alarm',
      'Chime',
    ]);
    expect(
      pinnedFavorite.where((sound) => sound.uri == 'content://bell'),
      hasLength(1),
    );
  });

  testWidgets('favorite sounds stay at the top and persist', (tester) async {
    remembered = 'content://beep';
    await openPicker(tester);

    expect(_soundOrder(tester), ['Beep', 'Default alarm', 'Chime', 'Bell']);
    final outlined = tester.widget<Icon>(
      find.descendant(
        of: _soundTile('Chime'),
        matching: find.byIcon(Icons.favorite_border),
      ),
    );
    expect(outlined.color, isNot(Colors.red));

    final previewsBefore = previews.length;
    await tester.tap(_favoriteButton(tester, 'Chime', favorite: false));
    await tester.pump();
    await tester.tap(_favoriteButton(tester, 'Beep', favorite: false));
    await tester.pump();

    expect(previews, hasLength(previewsBefore));
    expect(_soundOrder(tester), ['Beep', 'Chime', 'Default alarm', 'Bell']);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: _soundTile('Beep'),
              matching: find.byIcon(Icons.favorite),
            ),
          )
          .color,
      Colors.red,
    );
    expect(favorites, ['content://chime', 'content://beep']);
    expect(methods, isNot(contains('upsertAlarm')));

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();

    expect(_soundOrder(tester), ['Beep', 'Chime', 'Default alarm', 'Bell']);
    expect(
      find.descendant(
        of: _soundTile('Chime'),
        matching: find.byIcon(Icons.favorite),
      ),
      findsOneWidget,
    );

    await tester.tap(_favoriteButton(tester, 'Chime', favorite: true));
    await tester.pump();
    expect(_soundOrder(tester), ['Beep', 'Default alarm', 'Chime', 'Bell']);
    expect(
      find.descendant(
        of: _soundTile('Chime'),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

String _checkedTitle(WidgetTester tester) {
  final tile = tester.widget<ListTile>(
    find.ancestor(
      of: find.byIcon(Icons.check),
      matching: find.byType(ListTile),
    ),
  );
  final title = tile.title;
  if (title is! Text) return '';
  return title.data ?? '';
}

Finder _soundTile(String name) {
  return find.byWidgetPredicate((widget) {
    if (widget is! ListTile) return false;
    final title = widget.title;
    return title is Text && title.data == name;
  });
}

List<String> _soundOrder(WidgetTester tester) {
  return tester
      .widgetList<ListTile>(
        find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is Icon &&
                (widget.icon == Icons.favorite ||
                    widget.icon == Icons.favorite_border),
          ),
          matching: find.byType(ListTile),
        ),
      )
      .map((tile) => tile.title)
      .whereType<Text>()
      .map((title) => title.data ?? '')
      .toList();
}

Finder _favoriteButton(
  WidgetTester tester,
  String name, {
  required bool favorite,
}) {
  return find.descendant(
    of: _soundTile(name),
    matching: find.byTooltip(favorite ? 'Remove favorite' : 'Add favorite'),
  );
}
