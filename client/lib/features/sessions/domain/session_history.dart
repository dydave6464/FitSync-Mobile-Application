/// One finished workout, as the Progress tab lists it.
///
/// Deliberately not [ActiveSession]: that models a workout you are inside,
/// carrying every logged set so the logger can tick rows. This is a workout
/// you have left, summarised -- counts rather than contents, because a list
/// of past sessions that fetched every set of every one would grow without
/// bound to render numbers it then throws away.
class SessionHistoryEntry {
  const SessionHistoryEntry({
    required this.sessionId,
    required this.sessionDate,
    required this.setCount,
    required this.exerciseCount,
    this.startedAt,
    this.durationMin,
    this.totalVolumeKg,
    this.planName,
  });

  final int sessionId;

  /// `YYYY-MM-DD`, kept as a string for the same reason [ActiveSession] does:
  /// it is only ever compared and displayed, and parsing invites a timezone
  /// shift that moves a workout to the wrong day.
  final String sessionDate;

  final int setCount;
  final int exerciseCount;
  final DateTime? startedAt;

  /// Null for a session completed before durations were stamped.
  final int? durationMin;

  /// Null when nothing was logged with a weight -- a bodyweight-only session
  /// is not a zero-volume one, it is one volume does not describe.
  final double? totalVolumeKg;

  /// The plan this session ran under, or null when it was picked by hand.
  final String? planName;

  /// What to call it. A hand-picked session has no plan to borrow a name
  /// from, and "Session 32" tells the user nothing they wanted to know.
  String get title => planName ?? 'Your own workout';

  factory SessionHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SessionHistoryEntry(
        sessionId: json['sessionId'] as int,
        sessionDate: json['sessionDate'] as String,
        setCount: json['setCount'] as int? ?? 0,
        exerciseCount: json['exerciseCount'] as int? ?? 0,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.tryParse(json['startedAt'] as String),
        durationMin: json['durationMin'] as int?,
        // `as double?` would throw on a whole number: jsonDecode gives 2953 as
        // an int, and the server sends whatever MySQL's DECIMAL rounded to.
        // Same reasoning as LoggedSet.weightKg.
        totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble(),
        planName: json['planName'] as String?,
      );
}

/// A page of finished workouts.
class SessionHistoryPage {
  const SessionHistoryPage({
    required this.sessions,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<SessionHistoryEntry> sessions;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => page * limit < total;

  factory SessionHistoryPage.fromJson(Map<String, dynamic> json) =>
      SessionHistoryPage(
        sessions: (json['sessions'] as List<dynamic>? ?? const [])
            .map((e) => SessionHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        limit: json['limit'] as int? ?? 20,
      );
}

/// What a window of training added up to.
class TrainingSummary {
  const TrainingSummary({
    required this.sessionCount,
    required this.setCount,
    required this.totalVolumeKg,
  });

  final int sessionCount;
  final int setCount;
  final double totalVolumeKg;

  /// Nothing trained in this window. Distinct from a failure to load: the
  /// screen has to be able to say "nothing yet" plainly, which is the state
  /// every new account starts in.
  bool get isEmpty => sessionCount == 0;

  factory TrainingSummary.fromJson(Map<String, dynamic> json) => TrainingSummary(
        sessionCount: json['sessionCount'] as int? ?? 0,
        setCount: json['setCount'] as int? ?? 0,
        totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble() ?? 0,
      );
}
