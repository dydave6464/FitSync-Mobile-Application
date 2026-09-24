/// One day of the current week on the streak card.
class StreakDay {
  const StreakDay({required this.date, required this.active});

  /// `YYYY-MM-DD`, Manila.
  final String date;
  final bool active;

  factory StreakDay.fromJson(Map<String, dynamic> json) =>
      StreakDay(date: json['date'] as String, active: json['active'] as bool);
}

/// GET /streak: days in a row with any activity -- a habit ticked or a
/// workout finished -- as of the server's today.
class Streak {
  const Streak({
    required this.current,
    required this.best,
    required this.todayActive,
    required this.week,
  });

  final int current;
  final int best;
  final bool todayActive;

  /// Monday first.
  final List<StreakDay> week;

  factory Streak.fromJson(Map<String, dynamic> json) => Streak(
    current: json['current'] as int,
    best: json['best'] as int,
    todayActive: json['todayActive'] as bool,
    week: (json['week'] as List<dynamic>)
        .map((d) => StreakDay.fromJson(d as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// A lift target and how close the user's logged sets have come to it.
class LiftGoal {
  const LiftGoal({
    required this.goalId,
    required this.exerciseId,
    required this.exerciseName,
    required this.targetKg,
    required this.bestKg,
    required this.reachedOn,
  });

  final int goalId;
  final int exerciseId;
  final String exerciseName;
  final double targetKg;

  /// The heaviest counting set, or null when the lift was never logged.
  final double? bestKg;

  /// `YYYY-MM-DD` of the first set at or over the target, or null.
  final String? reachedOn;

  bool get reached => reachedOn != null;

  /// 0..1, for the progress bar.
  double get progress =>
      reached ? 1 : ((bestKg ?? 0) / targetKg).clamp(0.0, 1.0);

  factory LiftGoal.fromJson(Map<String, dynamic> json) => LiftGoal(
    goalId: json['goalId'] as int,
    exerciseId: json['exerciseId'] as int,
    exerciseName: json['exerciseName'] as String,
    targetKg: (json['targetKg'] as num).toDouble(),
    bestKg: (json['bestKg'] as num?)?.toDouble(),
    reachedOn: json['reachedOn'] as String?,
  );
}

/// A "Lifted before" row in the add-goal sheet.
class GoalOption {
  const GoalOption({
    required this.exerciseId,
    required this.name,
    required this.bestKg,
    required this.sets,
  });

  final int exerciseId;
  final String name;
  final double bestKg;
  final int sets;

  factory GoalOption.fromJson(Map<String, dynamic> json) => GoalOption(
    exerciseId: json['exerciseId'] as int,
    name: json['name'] as String,
    bestKg: (json['bestKg'] as num).toDouble(),
    sets: json['sets'] as int,
  );
}

const _months = [
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

/// `2026-09-12` -> `12 Sep`; the year is added when it is not [currentYear].
String formatReachedOn(String date, {required int currentYear}) {
  final d = DateTime.parse(date);
  final dayMonth = '${d.day} ${_months[d.month - 1]}';
  return d.year == currentYear ? dayMonth : '$dayMonth ${d.year}';
}
