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

class RecoveryOverview {
  const RecoveryOverview({
    required this.todayCheckin,
    required this.latestEstimate,
    required this.load,
  });

  final MorningCheckin? todayCheckin;
  final InjuryRiskEstimate? latestEstimate;
  final List<VolumeBucket> load;

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
      );
}
