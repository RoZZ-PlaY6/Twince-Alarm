import 'package:flutter_test/flutter_test.dart';
import 'package:twince_alarm/models/timer_session.dart';

void main() {
  test('duration changes stay inside hours, minutes, and seconds', () {
    final session = TimerSession();
    session.change(seconds: 1);
    session.change(minutes: 70);
    session.change(hours: 30);
    expect(session.selected, const Duration(hours: 23, minutes: 59, seconds: 1));
    expect(formatTimerDuration(session.selected), '23:59:01');
    session.change(seconds: -5);
    expect(session.selected.inSeconds.remainder(60), 0);
  });

  test('zero duration cannot start', () {
    final session = TimerSession();
    expect(session.canStart, isFalse);
    expect(session.start(), isFalse);
    expect(session.running, isFalse);
  });

  test('quick durations replace the selection', () {
    final session = TimerSession();
    session.setDuration(const Duration(minutes: 10));
    expect(formatTimerDuration(session.selected), '00:10:00');
    session.setDuration(const Duration(minutes: 15));
    expect(formatTimerDuration(session.selected), '00:15:00');
    session.setDuration(const Duration(minutes: 30));
    expect(formatTimerDuration(session.selected), '00:30:00');
  });

  test('countdown reaches zero and can pause, resume, and reset', () {
    final session = TimerSession();
    session.setDuration(const Duration(seconds: 3));
    expect(session.start(), isTrue);
    expect(formatTimerDuration(session.shown), '00:00:03');

    expect(session.tick(), isFalse);
    expect(formatTimerDuration(session.shown), '00:00:02');
    session.pause();
    expect(session.tick(), isFalse);
    expect(formatTimerDuration(session.shown), '00:00:02');
    session.resume();
    expect(session.tick(), isFalse);
    expect(formatTimerDuration(session.shown), '00:00:01');
    expect(session.tick(), isTrue);
    expect(formatTimerDuration(session.shown), '00:00:00');
    expect(session.running, isFalse);

    session.setDuration(const Duration(seconds: 2));
    session.start();
    session.reset();
    expect(session.running, isFalse);
    expect(formatTimerDuration(session.shown), '00:00:02');
  });

  test('timer sound is stored separately from the countdown', () {
    final session = TimerSession();
    session.selectSound(name: 'Beep', uri: 'content://beep');
    session.setDuration(const Duration(seconds: 1));
    session.start();
    expect(session.soundName, 'Beep');
    expect(session.soundUri, 'content://beep');
    expect(session.tick(), isTrue);
    expect(session.soundUri, 'content://beep');
  });
}
