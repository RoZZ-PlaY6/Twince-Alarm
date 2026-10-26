/// Plan-specific week rule. This is not claimed to be Twince's own calendar.
///
/// ISO-8601 week numbers are used (Monday-start weeks, week 1 contains the
/// year's first Thursday). An odd ISO week is Z because Twince exports Z as
/// `weekType: "odd"`. An even ISO week is F because Twince exports F as
/// `weekType: "even"`.
int isoWeekNumber(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final first = DateTime(thursday.year, 1, 1);
  return ((thursday.difference(first).inDays) ~/ 7) + 1;
}

/// `odd` ISO week -> Z, `even` ISO week -> F.
String planWeekLabel(DateTime date) => isoWeekNumber(date).isOdd ? 'Z' : 'F';

/// Empty or both Z and F means the alarm is active every week.
bool planWeekMatches(DateTime date, List<String> weekTags) {
  final tags = weekTags
      .map((tag) => tag.toUpperCase())
      .where((tag) => tag == 'Z' || tag == 'F')
      .toSet();
  if (tags.length != 1) return true;
  return tags.contains(planWeekLabel(date));
}
