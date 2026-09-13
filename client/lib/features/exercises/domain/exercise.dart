/// One row in the catalogue list. Deliberately has no animation — a list
/// response carries thumbnails only, so it stays small.
class ExerciseSummary {
  const ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.thumbnailUrl,
    this.contraindicated = false,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipment;
  final String? thumbnailUrl;

  /// Whether this exercise loads a region the signed-in user has reported an
  /// injury in. The catalogue marks rather than hides them, so the decision
  /// stays with whoever is picking.
  ///
  /// Defaults to false so a payload from before the field existed reads as
  /// "nothing known", never as a crash.
  final bool contraindicated;

  factory ExerciseSummary.fromJson(Map<String, dynamic> json) => ExerciseSummary(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        muscleGroup: json['muscleGroup'] as String,
        equipment: json['equipment'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        contraindicated: json['contraindicated'] as bool? ?? false,
      );
}

class ExerciseDetail {
  const ExerciseDetail({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.thumbnailUrl,
    required this.animationUrl,
    required this.cues,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipment;
  final String? thumbnailUrl;
  final String? animationUrl;
  final List<String> cues;

  factory ExerciseDetail.fromJson(Map<String, dynamic> json) => ExerciseDetail(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String,
        muscleGroup: json['muscleGroup'] as String,
        equipment: json['equipment'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        animationUrl: json['animationUrl'] as String?,
        cues: (json['cues'] as List<dynamic>? ?? const [])
            .map((c) => c as String)
            .toList(growable: false),
      );
}

class ExercisePage {
  const ExercisePage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<ExerciseSummary> items;
  final int page;
  final int limit;
  final int total;

  bool get hasMore => page * limit < total;

  factory ExercisePage.fromJson(Map<String, dynamic> json) => ExercisePage(
        items: (json['exercises'] as List<dynamic>)
            .map((e) => ExerciseSummary.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
      );
}
