import '../../../core/dates.dart';
import '../../../core/manila_day.dart';

/// How many days each period covers, as `SUMMARY_WINDOWS` in
/// `server/src/db/sessions.js` has them. The server splits that window into
/// equal buckets ending today, oldest first, so the dates each bucket covers
/// can be worked out here from its position alone.
const _periodDays = {'week': 7, 'month': 30, 'year': 365};

/// Today as the server counts its buckets: the Manila calendar day, which is
/// what CURDATE() means there (see manila_day.dart), not the phone's own.
DateTime volumeToday([DateTime? now]) =>
    DateTime.parse(manilaDayOf(now ?? DateTime.now()));

/// What a volume bucket is called: [axis] under its bar, [full] when it is
/// touched or read aloud.
///
/// The server labels buckets by how far back they are ("-6d", "-2m"), which
/// is how it counts, not how anyone reads a week. A week's bars are named by
/// day, a month's by the date each five-day span ends, and a year's by the
/// month most of each span falls in.
///
/// [axis] is empty for a bar left unlabelled: a year's twelve month names do
/// not fit under twelve bars on a phone, so every other one is shown,
/// counting back from the newest so the current span is always named.
///
/// A period this does not know keeps [fallback], the server's own label.
({String axis, String full}) volumeBucketName({
  required String period,
  required int index,
  required int count,
  required String fallback,
  required DateTime today,
}) {
  final days = _periodDays[period];
  if (days == null || count <= 0) return (axis: fallback, full: fallback);

  // Counted in UTC, which has no clock changes. In local time a day the
  // clocks went forward is 23 hours, and subtracting whole days from it
  // landed on the day before: a week lost its Sunday.
  DateTime back(int n) => DateTime.utc(today.year, today.month, today.day - n);
  String dated(DateTime day) => day.year == today.year
      ? shortDate(day)
      : '${shortDate(day)}, ${day.year}';

  final width = (days / count).ceil();
  final behind = count - 1 - index; // buckets between this one and today's
  final end = back(behind * width);
  // The window is the last [days] days, so the oldest span can be cut short.
  final earliest = back(days - 1);
  final start = back(behind * width + width - 1).isBefore(earliest)
      ? earliest
      : back(behind * width + width - 1);

  if (width == 1) {
    return (
      axis: weekdayShort[end.weekday - 1],
      full: behind == 0
          ? 'Today'
          : '${weekdayShort[end.weekday - 1]}, ${dated(end)}',
    );
  }

  final full = start.year == end.year
      ? '${shortDate(start)} – ${dated(end)}'
      : '${dated(start)} – ${dated(end)}';
  if (period == 'year') {
    // Named by its middle: a span ending October 2 is September with two
    // days of October, not October.
    final middle = back(behind * width + width ~/ 2);
    return (
      axis: behind.isEven ? monthShort[middle.month - 1] : '',
      full: full,
    );
  }
  return (axis: shortDate(end), full: full);
}
