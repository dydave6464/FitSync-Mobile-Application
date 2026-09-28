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
/// usual (null until three earlier days have steps).
class ActivityWeek {
  const ActivityWeek({
    required this.days,
    required this.usual,
    required this.missing,
  });

  final List<ActivityDay> days;
  final int? usual;

  /// `height` / `weight` absent from the profile, blocking km and/or kcal.
  final List<String> missing;

  bool get missingHeight => missing.contains('height');
  bool get missingWeight => missing.contains('weight');
  ActivityDay get today => days.last;

  /// Average steps over the days that have any, for "avg N.Nk/day".
  int? get average {
    final withData = [for (final d in days) if (d.steps != null) d.steps!];
    if (withData.isEmpty) return null;
    return (withData.reduce((a, b) => a + b) / withData.length).round();
  }

  factory ActivityWeek.fromJson(Map<String, dynamic> json) => ActivityWeek(
    days: (json['days'] as List<dynamic>)
        .map((d) => ActivityDay.fromJson(d as Map<String, dynamic>))
        .toList(growable: false),
    usual: json['usual'] as int?,
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

/// The line under the Activity screen's bar.
String usualLine({required int today, required int? usual}) {
  if (usual == null) return 'Your usual appears after 3 days of walking';
  final diff = today - usual;
  if (diff.abs() <= usual * 0.01) return 'Matched your usual';
  return diff > 0
      ? '${formatSteps(diff)} above your usual'
      : '${formatSteps(-diff)} to reach your usual';
}

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
