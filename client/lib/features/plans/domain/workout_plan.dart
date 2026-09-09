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
        dayNo: json['dayNo'] as int,
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
