import '../../../core/manila_day.dart';

/// One day of GET /activity. [steps] is null when nothing was saved that day.
/// The estimates are the server's; a missing one arrives as 0 and
/// [ActivityWeek.missing] says which to show as "—".
class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.steps,
    required this.caloriesBurned,
    required this.distanceKm,
    required this.activeMinutes,
  });

  /// `YYYY-MM-DD`, Manila.
  final String date;
  final int? steps;
  final int? caloriesBurned;
  final double? distanceKm;
  final int? activeMinutes;

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
    date: json['date'] as String,
    steps: json['steps'] as int?,
    caloriesBurned: json['caloriesBurned'] as int?,
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    activeMinutes: json['activeMinutes'] as int?,
  );
}

/// GET /activity: the seven days ending today, oldest first, and the user's
/// usual (null until [usualMinDays] earlier days have steps).
class ActivityWeek {
  const ActivityWeek({
    required this.days,
    required this.usual,
    required this.missing,
    this.usualDays,
  });

  final List<ActivityDay> days;
  final int? usual;

  /// How many earlier days of the week have steps: what the usual counts up
  /// to [usualMinDays] from. Null from a server that does not send it.
  final int? usualDays;

  /// `height` / `weight` absent from the profile, blocking km and/or kcal.
  final List<String> missing;

  bool get missingHeight => missing.contains('height');
  bool get missingWeight => missing.contains('weight');
  ActivityDay get today => days.last;

  /// Average steps over the days before today that have any, for "avg
  /// N.Nk/day": the same days the usual is worked out from, so the header
  /// and the bar above it measure against one baseline. Today's partial
  /// count would drag it down every morning.
  int? get average {
    if (days.isEmpty) return null;
    final withData = [
      for (final d in days.take(days.length - 1))
        if (d.steps != null) d.steps!,
    ];
    if (withData.isEmpty) return null;
    return (withData.reduce((a, b) => a + b) / withData.length).round();
  }

  factory ActivityWeek.fromJson(Map<String, dynamic> json) => ActivityWeek(
    days: (json['days'] as List<dynamic>)
        .map((d) => ActivityDay.fromJson(d as Map<String, dynamic>))
        .toList(growable: false),
    usual: json['usual'] as int?,
    usualDays: json['usualDays'] as int?,
    missing: (json['missing'] as List<dynamic>).cast<String>(),
  );
}

/// 6420 → "6,420".
String formatSteps(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Earlier days with steps the server needs before it works out a usual;
/// mirrors `USUAL_MIN_DAYS` in server/src/db/activity.js.
const usualMinDays = 3;

/// The line under the Activity screen's bar. Before there is a usual, it
/// counts down the days still needed, given [usualDays].
String usualLine({required int today, required int? usual, int? usualDays}) {
  if (usual == null) {
    final left = usualMinDays - (usualDays ?? 0);
    if (usualDays == null || usualDays <= 0 || left <= 0) {
      return 'Your usual appears after $usualMinDays days of walking';
    }
    return 'Your usual appears after $left more '
        '${left == 1 ? 'day' : 'days'} of walking';
  }
  final diff = today - usual;
  if (diff.abs() <= usual * 0.01) return 'Matched your usual';
  return diff > 0
      ? '${formatSteps(diff)} above your usual'
      : '${formatSteps(-diff)} to reach your usual';
}

/// The week card's per-day average: thousands to one decimal, as the
/// prototype writes it, and plain steps below a thousand ("avg 420/day"
/// rather than "avg 0.4k/day").
String perDayLine(int average) => average < 1000
    ? 'avg $average/day'
    : 'avg ${(average / 1000).toStringAsFixed(1)}k/day';

/// 00:00 in Manila on [now]'s Manila day, as a UTC instant: where "today"
/// starts for the step count, the same day the server saves it under.
DateTime manilaMidnight(DateTime now) {
  final day = manilaDayOf(now);
  return manilaInstant(
    DateTime.utc(
      int.parse(day.substring(0, 4)),
      int.parse(day.substring(5, 7)),
      int.parse(day.substring(8, 10)),
    ),
    '00:00',
  );
}
