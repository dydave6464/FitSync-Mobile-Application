import 'session_history.dart';

/// One finished workout opened from History: every exercise trained, with
/// the sets that were completed.
///
/// Read-only, unlike [ActiveSession]: a workout you have left is looked at,
/// never ticked. Only exercises with at least one completed set are listed,
/// in the order they were first logged.
class SessionDetail {
  const SessionDetail({
    required this.sessionId,
    required this.sessionDate,
    required this.setCount,
    required this.exercises,
    this.startedAt,
    this.durationMin,
    this.totalVolumeKg,
    this.planName,
    this.planDayNo,
    this.muscleGroups = const [],
  });

  final int sessionId;

  /// `YYYY-MM-DD`, kept as a string, as [SessionHistoryEntry.sessionDate].
  final String sessionDate;

  final int setCount;
  final DateTime? startedAt;
  final int? durationMin;
  final double? totalVolumeKg;
  final String? planName;
  final int? planDayNo;

  /// The same list a History row is named from, so both read the same title.
  final List<String> muscleGroups;

  final List<SessionDetailExercise> exercises;

  String get title => sessionTitle(planName, muscleGroups);

  factory SessionDetail.fromJson(Map<String, dynamic> json) => SessionDetail(
    sessionId: json['sessionId'] as int,
    sessionDate: json['sessionDate'] as String,
    setCount: json['setCount'] as int? ?? 0,
    startedAt: json['startedAt'] == null
        ? null
        : DateTime.tryParse(json['startedAt'] as String),
    durationMin: json['durationMin'] as int?,
    // `as num?` first: jsonDecode reads 2953 as an int.
    totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble(),
    planName: json['planName'] as String?,
    planDayNo: json['planDayNo'] as int?,
    muscleGroups: (json['muscleGroups'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(growable: false),
    exercises: (json['exercises'] as List<dynamic>? ?? const [])
        .map((e) => SessionDetailExercise.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
  );
}

/// One exercise of a finished workout, with its completed sets.
class SessionDetailExercise {
  const SessionDetailExercise({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.sets,
    this.equipment,
    this.thumbnailUrl,
    this.volumeKg,
  });

  final int exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipment;
  final String? thumbnailUrl;

  /// Null when no set carried both a weight and reps (bodyweight work).
  final double? volumeKg;

  final List<SessionDetailSet> sets;

  factory SessionDetailExercise.fromJson(Map<String, dynamic> json) =>
      SessionDetailExercise(
        exerciseId: json['exerciseId'] as int,
        name: json['name'] as String? ?? '',
        muscleGroup: json['muscleGroup'] as String? ?? '',
        equipment: json['equipment'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        volumeKg: (json['volumeKg'] as num?)?.toDouble(),
        sets: (json['sets'] as List<dynamic>? ?? const [])
            .map((e) => SessionDetailSet.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// One completed set. Either number may be missing: a bodyweight set has no
/// weight, and a set saved without reps has none.
class SessionDetailSet {
  const SessionDetailSet({required this.setNumber, this.weightKg, this.reps});

  final int setNumber;
  final double? weightKg;
  final int? reps;

  factory SessionDetailSet.fromJson(Map<String, dynamic> json) =>
      SessionDetailSet(
        setNumber: json['setNumber'] as int,
        // Same reasoning as LoggedSet.weightKg: 60 arrives as an int.
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        reps: json['reps'] as int?,
      );
}
