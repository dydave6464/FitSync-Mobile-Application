/// Short date words for charts and their tooltips: "Mon", "Sep 20".
///
/// English and fixed, like every other string in the app; there is no locale
/// to follow yet.
const monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Monday first, matching [DateTime.weekday] (1 is Monday).
const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Sep 20".
String shortDate(DateTime day) => '${monthShort[day.month - 1]} ${day.day}';

/// How a past day reads next to [today]: "Today", "Yesterday",
/// "Wed, Nov 4", and with its year once it is not today's year:
/// "Tue, Nov 4, 2025".
///
/// Only the calendar dates count; the times of day and the zones are
/// ignored. Callers decide which zone "today" belongs to (the app uses
/// Manila's, see manila_day.dart). One label for nutrition, sessions and
/// the weigh-in sheet, so a day reads the same wherever it is shown.
String calendarDayLabel(DateTime day, DateTime today) {
  // Whole days in UTC, which has no clock changes to make one 23 hours long.
  final d = DateTime.utc(day.year, day.month, day.day);
  final t = DateTime.utc(today.year, today.month, today.day);
  final behind = t.difference(d).inDays;
  if (behind == 0) return 'Today';
  if (behind == 1) return 'Yesterday';
  final named = '${weekdayShort[d.weekday - 1]}, ${shortDate(d)}';
  return d.year == t.year ? named : '$named, ${d.year}';
}
