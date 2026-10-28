/// Saturday–Friday week chosen by the user.
///
/// [anchorSaturday] is a local calendar date at midnight. [even] is the parity
/// of that Saturday–Friday week: true is Even (Z), false is Odd (F).
class WeekCycle {
  const WeekCycle({required this.anchorSaturday, required this.even});

  final DateTime anchorSaturday;
  final bool even;

  String get label => even ? 'Even (Z)' : 'Odd (F)';

  Map<String, Object?> toJson() {
    final day = dateOnly(anchorSaturday);
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return {'anchorSaturday': '${day.year}-$month-$date', 'even': even};
  }

  static WeekCycle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final anchor = raw['anchorSaturday'];
    final even = raw['even'];
    if (anchor is! String || even is! bool) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(anchor);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.month != month || parsed.day != day) return null;
    return WeekCycle(anchorSaturday: saturdayOnOrBefore(parsed), even: even);
  }
}

enum PlanRecurrence { odd, even, both }

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Saturday of the local calendar week that contains [value].
DateTime saturdayOnOrBefore(DateTime value) {
  final day = dateOnly(value);
  final sinceSaturday = (day.weekday + 1) % 7;
  return day.subtract(Duration(days: sinceSaturday));
}

int _calendarDays(DateTime start, DateTime end) {
  final a = DateTime.utc(start.year, start.month, start.day);
  final b = DateTime.utc(end.year, end.month, end.day);
  return b.difference(a).inDays;
}

/// Settings label for the Saturday–Friday week containing [now].
///
/// Even weeks are Z and odd weeks are F, matching the rest of Twince Alarm.
String settingsWeekLabel(WeekCycle cycle, DateTime now) {
  return isEvenWeek(cycle, now) ? 'هفته جاری: زوج (Z)' : 'هفته جاری: فرد (F)';
}

/// Visible Plan caption for the Saturday–Friday week containing [now].
String currentWeekCaption(WeekCycle cycle, DateTime now) {
  final even = isEvenWeek(cycle, now);
  return even ? 'Current week: Even (Z)' : 'Current week: Odd (F)';
}

/// Parity of [value] for [cycle]. The anchor week keeps [WeekCycle.even].
/// Each later or earlier Saturday flips it once.
bool isEvenWeek(WeekCycle cycle, DateTime value) {
  final weeks =
      _calendarDays(
        saturdayOnOrBefore(cycle.anchorSaturday),
        saturdayOnOrBefore(value),
      ) ~/
      7;
  final flipped = weeks.abs().isOdd;
  return flipped ? !cycle.even : cycle.even;
}

PlanRecurrence? recurrenceOf(List<String> weekTags) {
  final tags = weekTags.map((tag) => tag.trim().toLowerCase()).toSet();
  if (tags.isEmpty) return null;
  if (tags.length == 1 && (tags.contains('both') || tags.contains('every'))) {
    return PlanRecurrence.both;
  }
  // Z is an even week. F is an odd week. English words follow their own meaning.
  if (tags.length == 1 && (tags.contains('z') || tags.contains('even'))) {
    return PlanRecurrence.even;
  }
  if (tags.length == 1 && (tags.contains('f') || tags.contains('odd'))) {
    return PlanRecurrence.odd;
  }
  if (tags.contains('z') && tags.contains('f') && tags.length == 2) {
    return PlanRecurrence.both;
  }
  return null;
}

bool recurrenceEligible(PlanRecurrence recurrence, bool evenWeek) {
  switch (recurrence) {
    case PlanRecurrence.odd:
      return !evenWeek;
    case PlanRecurrence.even:
      return evenWeek;
    case PlanRecurrence.both:
      return true;
  }
}

/// Next local alarm instant. Manual alarms ([weekTags] empty) ignore parity.
/// Unknown plan tags, or plan tags without a [cycle], are not scheduled.
DateTime? nextLocalAlarm({
  required DateTime from,
  required int hour,
  required int minute,
  required List<int> repeatDays,
  required List<String> weekTags,
  WeekCycle? cycle,
}) {
  final recurrence = weekTags.isEmpty ? null : recurrenceOf(weekTags);
  if (weekTags.isNotEmpty && (recurrence == null || cycle == null)) return null;
  final limit =
      recurrence == PlanRecurrence.odd || recurrence == PlanRecurrence.even
      ? 21
      : 7;
  final start = dateOnly(from);
  for (var offset = 0; offset <= limit; offset++) {
    final day = DateTime(start.year, start.month, start.day + offset);
    if (repeatDays.isNotEmpty && !repeatDays.contains(day.weekday)) continue;
    if (repeatDays.isEmpty && offset > 1) break;
    final when = DateTime(day.year, day.month, day.day, hour, minute);
    if (!when.isAfter(from)) continue;
    if (recurrence != null &&
        !recurrenceEligible(recurrence, isEvenWeek(cycle!, when))) {
      continue;
    }
    return when;
  }
  return null;
}
