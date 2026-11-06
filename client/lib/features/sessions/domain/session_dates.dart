import '../../../core/dates.dart';
import '../../../core/manila_day.dart';

/// How a finished workout's day reads: "Today", "Yesterday", "Tue, Nov 4",
/// and with its year once it is not this year's: "Tue, Nov 4, 2025".
///
/// [sessionDate] is the server's `YYYY-MM-DD`, a Manila calendar day, so
/// "today" is Manila's too (see manila_day.dart) -- a phone set to another
/// zone still agrees about which workout was yesterday's. Anything that does
/// not parse is shown as it came, rather than hidden.
String sessionDayLabel(String sessionDate, {DateTime? now}) {
  final parsed = DateTime.tryParse(sessionDate);
  if (parsed == null) return sessionDate;
  // Whole days in UTC, which has no clock changes to make one 23 hours long.
  DateTime utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  final day = utcDay(parsed);
  final today = utcDay(DateTime.parse(manilaDayOf(now ?? DateTime.now())));

  final behind = today.difference(day).inDays;
  if (behind == 0) return 'Today';
  if (behind == 1) return 'Yesterday';
  final named = '${weekdayShort[day.weekday - 1]}, ${shortDate(day)}';
  return day.year == today.year ? named : '$named, ${day.year}';
}
