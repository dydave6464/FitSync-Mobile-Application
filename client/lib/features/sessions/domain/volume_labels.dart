import '../../../core/dates.dart';

/// How many days each period covers, as `SUMMARY_WINDOWS` in
/// `server/src/db/sessions.js` has them. The server splits that window into
/// equal buckets ending today, oldest first, so the dates each bucket covers
/// can be worked out here from its position alone.
const _periodDays = {'week': 7, 'month': 30, 'year': 365};

/// What a volume bucket is called: [axis] under its bar, [full] when it is
/// touched or read aloud.
///
/// The server labels buckets by how far back they are ("-6d", "-2m"), which
/// is how it counts, not how anyone reads a week. A week's bars are named by
/// day, a month's by the date each five-day span ends, and a year's by month.
///
/// [axis] is empty for a bar left unlabelled: a year's twelve month names do
/// not fit under twelve bars on a phone, so every other one is shown,
/// counting back from the newest so the current month is always named.
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

  final width = (days / count).ceil();
  final back = count - 1 - index; // buckets between this one and today's
  final day = DateTime(today.year, today.month, today.day);
  final end = day.subtract(Duration(days: back * width));
  final start = end.subtract(Duration(days: width - 1));

  if (width == 1) {
    return (
      axis: weekdayShort[end.weekday - 1],
      full: back == 0
          ? 'Today'
          : '${weekdayShort[end.weekday - 1]}, ${shortDate(end)}',
    );
  }

  final full = '${shortDate(start)} – ${shortDate(end)}';
  if (period == 'year') {
    return (axis: back.isEven ? monthShort[end.month - 1] : '', full: full);
  }
  return (axis: shortDate(end), full: full);
}
