/// What "Auto" would choose for this user now, from `GET /plans/defaults`:
/// the same derivation the generator runs, so the label never disagrees with
/// the plan Auto produces.
class PlanDefaults {
  const PlanDefaults({
    required this.sessionLengthMin,
    required this.exercisesPerDay,
    required this.lengthReason,
  });

  final int sessionLengthMin;
  final int exercisesPerDay;

  /// Why Auto picked [sessionLengthMin] (for example `health` or `level`),
  /// which decides the note shown when the user picks 60 instead.
  final String lengthReason;

  factory PlanDefaults.fromJson(Map<String, dynamic> json) => PlanDefaults(
    sessionLengthMin: json['sessionLengthMin'] as int,
    exercisesPerDay: json['exercisesPerDay'] as int,
    lengthReason: json['lengthReason'] as String? ?? '',
  );
}
