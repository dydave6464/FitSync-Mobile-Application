/// One prescribed exercise within a plan.
class PlanExercise {
  const PlanExercise({
    required this.planExerciseId,
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.orderNo,
    required this.targetSets,
    required this.targetReps,
    this.thumbnailUrl,
    this.equipment,
    this.dayNo = 1,
  });

  /// Identifies this row within the plan. Swapping addresses this, not
  /// [exerciseId], because the row survives the exercise being replaced.
  final int planExerciseId;

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final int orderNo;
  final int targetSets;

  /// Which rotation day this exercise belongs to. 1 for every plan generated
  /// before per-day splits, and for every full-body plan since.
  final int dayNo;

  /// A string, not a number: `plan_exercises.target_reps` is `VARCHAR(255)`
  /// and the generator writes ranges like "8-12". Typing this as an int
  /// crashes on every real plan.
  final String targetReps;

  /// A path relative to the API base, or null when the catalogue has no
  /// artwork for this exercise yet.
  final String? thumbnailUrl;

  /// The curated equipment name the server resolved for this exercise, or
  /// null — `exercises.equipment_id` is nullable.
  final String? equipment;

  factory PlanExercise.fromJson(Map<String, dynamic> json) => PlanExercise(
        planExerciseId: json['planExerciseId'] as int,
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        muscleGroup: json['muscleGroup'] as String? ?? '',
        orderNo: json['orderNo'] as int? ?? 0,
        targetSets: json['targetSets'] as int? ?? 0,
        // via toString() so a generator that writes a bare number into that
        // VARCHAR is handled too.
        targetReps: json['targetReps']?.toString() ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        equipment: json['equipment'] as String?,
        dayNo: json['dayNo'] as int? ?? 1,
      );
}

/// One day of a plan's rotation. The name is derived server-side from the
/// split style; the client only displays it.
class PlanDay {
  const PlanDay({required this.dayNo, required this.name});

  final int dayNo;
  final String name;

  factory PlanDay.fromJson(Map<String, dynamic> json) => PlanDay(
        dayNo: json['dayNo'] as int? ?? 1,
        name: json['name'] as String? ?? '',
      );
}

class WorkoutPlan {
  const WorkoutPlan({
    required this.planId,
    required this.name,
    required this.splitStyle,
    required this.daysPerWeek,
    required this.sessionLengthMin,
    required this.weekNo,
    required this.exercises,
    this.days = const [],
  });

  final int planId;
  final String name;
  final String splitStyle;
  final int daysPerWeek;
  final int sessionLengthMin;
  final int weekNo;
  final List<PlanExercise> exercises;

  /// The full rotation. Empty from a server that predates per-day plans, in
  /// which case the plan is a single unnamed day.
  final List<PlanDay> days;

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) => WorkoutPlan(
        planId: json['planId'] as int,
        name: json['name'] as String,
        splitStyle: json['splitStyle'] as String? ?? '',
        daysPerWeek: json['daysPerWeek'] as int? ?? 0,
        sessionLengthMin: json['sessionLengthMin'] as int? ?? 0,
        weekNo: json['weekNo'] as int? ?? 1,
        exercises: ((json['exercises'] as List<dynamic>?) ?? const [])
            .map((e) => PlanExercise.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        days: ((json['days'] as List<dynamic>?) ?? const [])
            .map((d) => PlanDay.fromJson(d as Map<String, dynamic>))
            .toList(growable: false),
      );

  /// Which rotation day today falls on, from how many sessions are already
  /// complete this week.
  ///
  /// Mirrors nextPlanDayNo in `server/src/db/sessions.js`: the day advances
  /// with completed sessions, not with the calendar, so a missed day costs a
  /// day rather than a session. The fourth session of a three-day rotation
  /// is day 1 again, which is what a four-day push/pull/legs week is.
  ///
  /// This is a display-only preview and can disagree with the server by one
  /// step: its callers pass the number of DISTINCT completed session dates,
  /// while the server counts sessions with COUNT(*), so someone who trains
  /// twice on one date advances the server's rotation twice and this
  /// preview's once. It is superseded the moment a session starts -- the
  /// logger reads that session's own stamped `planDayNo`, never this.
  ///
  /// A plan with no [days] is a one-day plan, which is what a flat ordered
  /// list already means -- and what stops a zero rotation dividing by zero.
  int todayDayNo(int completedSessions) {
    final rotation = days.isEmpty ? 1 : days.length;
    return (completedSessions % rotation) + 1;
  }

  /// The exercises for one rotation day, in order.
  ///
  /// A null day is a session stamped before migration 013; it reads as day 1,
  /// which is what its plan was.
  List<PlanExercise> exercisesForDay(int? dayNo) {
    final day = dayNo ?? 1;
    return exercises.where((e) => e.dayNo == day).toList(growable: false);
  }
}

/// Turns a `split_style` slug into something readable without pretending to
/// know every value the generator might produce.
String describeSplit(String slug) {
  if (slug.isEmpty) return '';
  return slug
      .split('_')
      .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
