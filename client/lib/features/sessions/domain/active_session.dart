/// One set the user has completed and the server has stored.
class LoggedSet {
  const LoggedSet({
    required this.exerciseId,
    required this.setNumber,
    this.weightKg,
    this.reps,
  });

  final int exerciseId;
  final int setNumber;

  /// Null for a bodyweight exercise, which has no external load.
  final double? weightKg;

  /// Null when the plan prescribed AMRAP and the user did not count.
  final int? reps;

  factory LoggedSet.fromJson(Map<String, dynamic> json) => LoggedSet(
        exerciseId: json['exerciseId'] as int,
        setNumber: json['setNumber'] as int,
        // `as double?` would throw on a whole number: jsonDecode gives 20 as
        // an int, and the server sends whatever MySQL's DECIMAL rounded to.
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        reps: json['reps'] as int?,
      );
}

class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    required this.status,
    required this.sessionDate,
    this.planId,
    this.startedAt,
    this.durationMin,
    this.totalVolumeKg,
    this.sets = const [],
  });

  final int sessionId;

  /// One of `in_progress`, `completed`, `abandoned`.
  final String status;

  /// `YYYY-MM-DD`, formatted server-side in the server's local time. Kept as a
  /// string because it is only ever compared against the week strip's dates,
  /// and parsing it to a DateTime would invite a timezone shift that moves the
  /// dot to the wrong day.
  final String sessionDate;

  final int? planId;
  final DateTime? startedAt;
  final int? durationMin;
  final double? totalVolumeKg;
  final List<LoggedSet> sets;

  bool get isInProgress => status == 'in_progress';

  int get completedSetCount => sets.length;

  LoggedSet? setFor(int exerciseId, int setNumber) {
    for (final set in sets) {
      if (set.exerciseId == exerciseId && set.setNumber == setNumber) return set;
    }
    return null;
  }

  /// Replaces or adds one set, leaving everything else alone — how the
  /// controller folds a single write back into state without refetching.
  ActiveSession withSet(LoggedSet set) {
    final next = [
      for (final existing in sets)
        if (existing.exerciseId != set.exerciseId || existing.setNumber != set.setNumber)
          existing,
      set,
    ]..sort((a, b) => a.exerciseId == b.exerciseId
        ? a.setNumber.compareTo(b.setNumber)
        : a.exerciseId.compareTo(b.exerciseId));
    return _copyWith(sets: next);
  }

  ActiveSession withoutSet(int exerciseId, int setNumber) => _copyWith(
        sets: [
          for (final set in sets)
            if (set.exerciseId != exerciseId || set.setNumber != setNumber) set,
        ],
      );

  ActiveSession _copyWith({List<LoggedSet>? sets}) => ActiveSession(
        sessionId: sessionId,
        status: status,
        sessionDate: sessionDate,
        planId: planId,
        startedAt: startedAt,
        durationMin: durationMin,
        totalVolumeKg: totalVolumeKg,
        sets: sets ?? this.sets,
      );

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
        sessionId: json['sessionId'] as int,
        status: json['status'] as String,
        sessionDate: json['sessionDate'] as String,
        planId: json['planId'] as int?,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String),
        durationMin: json['durationMin'] as int?,
        totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble(),
        sets: ((json['sets'] as List<dynamic>?) ?? const [])
            .map((e) => LoggedSet.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// What the user last lifted on one exercise — the heaviest set of their most
/// recent completed session.
class LastPerformance {
  const LastPerformance({
    required this.exerciseId,
    required this.sessionDate,
    this.weightKg,
    this.reps,
  });

  final int exerciseId;
  final String sessionDate;
  final double? weightKg;
  final int? reps;

  factory LastPerformance.fromJson(Map<String, dynamic> json) => LastPerformance(
        exerciseId: json['exerciseId'] as int,
        sessionDate: json['sessionDate'] as String,
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        reps: json['reps'] as int?,
      );
}
