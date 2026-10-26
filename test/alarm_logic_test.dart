import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/models/alarm_item.dart';

AlarmItem _alarm({
  int hour = 7,
  int minute = 30,
  bool enabled = true,
  List<int> days = const [],
}) {
  return AlarmItem(
    id: 1,
    hour: hour,
    minute: minute,
    label: 'Morning workout',
    subtitle: 'Time to start your task',
    enabled: enabled,
    vibrate: true,
    soundUri: '',
    repeatDays: days,
  );
}

void main() {
  test('one-time alarm later today stays today', () {
    final from = DateTime(2026, 10, 26, 6);
    final next = nextTrigger(_alarm(), from);
    expect(next, DateTime(2026, 10, 26, 7, 30));
  });

  test('one-time alarm that already passed rolls to tomorrow', () {
    final from = DateTime(2026, 10, 26, 8);
    final next = nextTrigger(_alarm(), from);
    expect(next, DateTime(2026, 10, 27, 7, 30));
  });

  test('weekday repeat skips days that are not selected', () {
    final from = DateTime(2026, 10, 26, 8);
    final next = nextTrigger(_alarm(days: const [2]), from);
    expect(next, DateTime(2026, 10, 27, 7, 30));
    expect(next!.weekday, 2);
  });

  test('disabled alarms have no next trigger', () {
    expect(nextTrigger(_alarm(enabled: false), DateTime(2026, 10, 26, 6)), isNull);
  });

  test('repeat labels use the clock-app names', () {
    expect(repeatLabel(const []), 'Once');
    expect(repeatLabel(const [1, 2, 3, 4, 5]), 'Weekdays');
    expect(repeatLabel(const [1, 2, 3, 4, 5, 6, 7]), 'Every day');
  });
}
