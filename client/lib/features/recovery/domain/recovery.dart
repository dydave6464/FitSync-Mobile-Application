import '../../sessions/domain/training_analytics.dart' show VolumeBucket;

/// One morning's answers. The four values are the server's ENUM spellings and
/// are never transformed on the way through -- ml/app/risk.py looks them up
/// with a defaulting get, so a renamed value scores zero penalty in silence.
class MorningCheckin {
  const MorningCheckin({
    required this.checkinId,
    required this.checkinDate,
    required this.sleepQuality,
    required this.muscleSoreness,
    required this.energy,
    required this.stress,
  });

  final int checkinId;
  final String checkinDate;
  final String sleepQuality;
  final String muscleSoreness;
  final String energy;
  final String stress;

  factory MorningCheckin.fromJson(Map<String, dynamic> json) => MorningCheckin(
    checkinId: json['checkinId'] as int,
    checkinDate: json['checkinDate'] as String,
    sleepQuality: json['sleepQuality'] as String,
    muscleSoreness: json['muscleSoreness'] as String,
    energy: json['energy'] as String,
    stress: json['stress'] as String,
  );
}

class InjuryRiskEstimate {
  const InjuryRiskEstimate({
    required this.riskLevel,
    required this.trainingLoadScore,
    required this.checkinDate,
  });

  /// 'low', 'moderate' or 'high'.
  final String riskLevel;
  final double? trainingLoadScore;
  final String checkinDate;

  /// How far round the ring to draw.
  ///
  /// Keyed off the level rather than the raw score: the score is a 0-100
  /// internal figure whose thresholds live in risk.py, and drawing it directly
  /// would put the arc and the word it sits under out of step the day those
  /// thresholds move.
  double get ringValue => switch (riskLevel) {
    'high' => 0.9,
    'moderate' => 0.55,
    _ => 0.2,
  };

  String get label => switch (riskLevel) {
    'high' => 'High',
    'moderate' => 'Moderate',
    _ => 'Low',
  };

  factory InjuryRiskEstimate.fromJson(Map<String, dynamic> json) =>
      InjuryRiskEstimate(
        riskLevel: json['riskLevel'] as String,
        trainingLoadScore: (json['trainingLoadScore'] as num?)?.toDouble(),
        checkinDate: json['checkinDate'] as String,
      );
}

/// When one muscle group was last trained, from GET /recovery.
///
/// A dated fact, not a readiness score: the app has no model of how recovered
/// a muscle is, so the card says when, never how ready.
class MuscleRecency {
  const MuscleRecency({
    required this.group,
    required this.lastTrained,
    required this.daysAgo,
  });

  /// chest, back, shoulders, arms, legs or core.
  final String group;

  /// `YYYY-MM-DD`, or null when never trained.
  final String? lastTrained;
  final int? daysAgo;

  /// The group as the card shows it: `legs` -> `Legs`.
  String get label =>
      group.isEmpty ? group : '${group[0].toUpperCase()}${group.substring(1)}';

  /// "Today", "Yesterday", "5 days ago", or "Not trained yet".
  String get when => switch (daysAgo) {
    null => 'Not trained yet',
    0 => 'Today',
    1 => 'Yesterday',
    final n => '$n days ago',
  };

  factory MuscleRecency.fromJson(Map<String, dynamic> json) => MuscleRecency(
    group: json['group'] as String,
    lastTrained: json['lastTrained'] as String?,
    daysAgo: json['daysAgo'] as int?,
  );
}

class RecoveryOverview {
  const RecoveryOverview({
    required this.todayCheckin,
    required this.latestEstimate,
    required this.load,
    this.muscles = const [],
  });

  final MorningCheckin? todayCheckin;
  final InjuryRiskEstimate? latestEstimate;
  final List<VolumeBucket> load;

  /// Longest rested first, as the server orders them.
  final List<MuscleRecency> muscles;

  factory RecoveryOverview.fromJson(Map<String, dynamic> json) =>
      RecoveryOverview(
        todayCheckin: json['todayCheckin'] == null
            ? null
            : MorningCheckin.fromJson(
                json['todayCheckin'] as Map<String, dynamic>,
              ),
        latestEstimate: json['latestEstimate'] == null
            ? null
            : InjuryRiskEstimate.fromJson(
                json['latestEstimate'] as Map<String, dynamic>,
              ),
        load: [
          for (final b in (json['load'] as List<dynamic>? ?? const []))
            VolumeBucket.fromJson(b as Map<String, dynamic>),
        ],
        muscles: [
          for (final m in (json['muscles'] as List<dynamic>? ?? const []))
            MuscleRecency.fromJson(m as Map<String, dynamic>),
        ],
      );
}
