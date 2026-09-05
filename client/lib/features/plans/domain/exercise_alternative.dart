/// A swap candidate. Deliberately not a [PlanExercise]: it has no slot, sets
/// or reps, because those belong to the plan row it would replace, not to the
/// exercise.
class ExerciseAlternative {
  const ExerciseAlternative({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    this.equipment,
    this.thumbnailUrl,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipment;
  final String? thumbnailUrl;

  factory ExerciseAlternative.fromJson(Map<String, dynamic> json) =>
      ExerciseAlternative(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        muscleGroup: json['muscleGroup'] as String? ?? '',
        equipment: json['equipment'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
      );
}
