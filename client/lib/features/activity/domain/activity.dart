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

  /// This day with its step count moved on to [liveSteps]. The server
  /// works the estimates out from the count it last saved, up to five
  /// minutes behind the phone's, so they are carried along to the live
  /// count rather than sitting still beside it. Home and the Activity
  /// screen both read today through this, so the two never show different
  /// kcal or km for the same count.
  ///
  /// With the server's [perStep] factors, each estimate is worked out
  /// afresh, rounded as the server rounds (server/src/lib/
  /// activity-estimate.js), so it is the figure the server will save for
  /// that count, and it grows from a day saved at 0 steps too. A null
  /// factor (no height or weight) keeps the stored value, which the screens
  /// show as "—" through [ActivityWeek.missing].
  ///
  /// Without them (an older server), the saved estimates grow by the share
  /// the count has grown; with nothing saved to grow from, they stay as
  /// they are.
  ActivityDay grownTo(int liveSteps, {ActivityPerStep? perStep}) {
    if (perStep != null) {
      final km = perStep.distanceKm;
      final kcal = perStep.caloriesBurned;
      return ActivityDay(
        date: date,
        steps: liveSteps,
        caloriesBurned: kcal == null
            ? caloriesBurned
            : (liveSteps * kcal).round(),
        distanceKm: km == null
            ? distanceKm
            : (liveSteps * km * 100).round() / 100,
        activeMinutes: (liveSteps * perStep.activeMinutes).round(),
      );
    }
    final saved = steps;
    final factor = saved != null && saved > 0 ? liveSteps / saved : 1.0;
    return ActivityDay(
      date: date,
      steps: liveSteps,
      caloriesBurned: caloriesBurned == null
          ? null
          : (caloriesBurned! * factor).round(),
      distanceKm: distanceKm == null ? null : distanceKm! * factor,
      activeMinutes: activeMinutes == null
          ? null
          : (activeMinutes! * factor).round(),
    );
  }

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
    date: json['date'] as String,
    steps: json['steps'] as int?,
    caloriesBurned: json['caloriesBurned'] as int?,
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    activeMinutes: json['activeMinutes'] as int?,
  );
}

/// What one step adds to each estimate, for the profile as it is now:
/// `perStep` in GET /activity, unrounded. [distanceKm] is null without a
/// height, and [caloriesBurned] without a height or a weight.
class ActivityPerStep {
  const ActivityPerStep({
    required this.distanceKm,
    required this.caloriesBurned,
    required this.activeMinutes,
  });

  final double? distanceKm;
  final double? caloriesBurned;
  final double activeMinutes;

  factory ActivityPerStep.fromJson(Map<String, dynamic> json) =>
      ActivityPerStep(
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        caloriesBurned: (json['caloriesBurned'] as num?)?.toDouble(),
        activeMinutes: (json['activeMinutes'] as num).toDouble(),
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
    this.perStep,
  });

  final List<ActivityDay> days;
  final int? usual;

  /// How many earlier days of the week have steps: what the usual counts up
  /// to [usualMinDays] from. Null from a server that does not send it.
  final int? usualDays;

  /// `height` / `weight` absent from the profile, blocking km and/or kcal.
  final List<String> missing;

  /// The factors that work today's estimates out for a live count (see
  /// [ActivityDay.grownTo]). Null from a server that does not send them.
  final ActivityPerStep? perStep;

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
    perStep: json['perStep'] is Map<String, dynamic>
        ? ActivityPerStep.fromJson(json['perStep'] as Map<String, dynamic>)
        : null,
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
