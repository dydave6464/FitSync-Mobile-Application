/// One prescribed exercise within a plan.
class PlanExercise {
  const PlanExercise({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.orderNo,
    required this.targetSets,
    required this.targetReps,
    this.thumbnailUrl,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final int orderNo;
  final int targetSets;
  final int targetReps;

  /// A path relative to the API base, or null when the catalogue has no
  /// artwork for this exercise yet.
  final String? thumbnailUrl;

  factory PlanExercise.fromJson(Map<String, dynamic> json) => PlanExercise(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        muscleGroup: json['muscleGroup'] as String? ?? '',
        orderNo: json['orderNo'] as int? ?? 0,
        targetSets: json['targetSets'] as int? ?? 0,
        targetReps: json['targetReps'] as int? ?? 0,
        thumbnailUrl: json['thumbnailUrl'] as String?,
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
  });

  final int planId;
  final String name;
  final String splitStyle;
  final int daysPerWeek;
  final int sessionLengthMin;
  final int weekNo;
  final List<PlanExercise> exercises;

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
      );
}
