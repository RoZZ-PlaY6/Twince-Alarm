/// Foreground countdown. This is not an alarm and does not touch alarm storage.
class TimerSession {
  static const maxHours = 23;

  Duration selected = Duration.zero;
  Duration remaining = Duration.zero;
  bool running = false;
  bool paused = false;
  bool finished = false;
  String soundUri = '';
  String soundName = 'Default alarm';

  Duration get shown => (running || paused || finished) ? remaining : selected;

  bool get canStart => !running && !paused && selected > Duration.zero;

  void setDuration(Duration value) {
    if (running || paused) return;
    finished = false;
    selected = _clamp(value);
  }

  void change({int hours = 0, int minutes = 0, int seconds = 0}) {
    if (running || paused) return;
    finished = false;
    final nextHours = (selected.inHours + hours).clamp(0, maxHours);
    final nextMinutes = (selected.inMinutes.remainder(60) + minutes).clamp(0, 59);
    final nextSeconds = (selected.inSeconds.remainder(60) + seconds).clamp(0, 59);
    selected = Duration(hours: nextHours, minutes: nextMinutes, seconds: nextSeconds);
  }

  void selectSound({required String name, required String uri}) {
    soundName = name.trim().isEmpty ? 'Default alarm' : name.trim();
    soundUri = uri;
  }

  /// Starts [selected]. Returns false when the duration is zero.
  bool start() {
    if (!canStart) return false;
    remaining = selected;
    running = true;
    paused = false;
    finished = false;
    return true;
  }

  /// Starts a separate countdown, such as a snooze, without changing [selected].
  bool startFor(Duration length) {
    final next = _clamp(length);
    if (next <= Duration.zero) return false;
    remaining = next;
    running = true;
    paused = false;
    finished = false;
    return true;
  }

  void pause() {
    if (running && !paused) paused = true;
  }

  void resume() {
    if (paused && remaining > Duration.zero) {
      paused = false;
      running = true;
    }
  }

  void reset() {
    running = false;
    paused = false;
    finished = false;
    remaining = Duration.zero;
  }

  /// Advances one second. Returns true when the countdown reaches zero.
  bool tick() {
    if (!running || paused) return false;
    if (remaining <= const Duration(seconds: 1)) {
      remaining = Duration.zero;
      running = false;
      paused = false;
      finished = true;
      return true;
    }
    remaining -= const Duration(seconds: 1);
    return false;
  }

  static Duration _clamp(Duration value) {
    if (value <= Duration.zero) return Duration.zero;
    final hours = value.inHours.clamp(0, maxHours);
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }
}

String formatTimerDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours.clamp(0, 99);
  final minutes = safe.inMinutes.remainder(60);
  final seconds = safe.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
