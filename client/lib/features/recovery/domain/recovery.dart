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

/// One input that raised an estimate, from the ML service's `drivers`.
///
/// [value] is whatever the contract sends for that [key]: a number for
/// `load` (percent above the usual week) and `injury_history` (a count), and
/// the 3-day worst answer as a string for the check-in questions and
/// `recent_pain`.
class RiskDriver {
  const RiskDriver({required this.key, required this.value});

  final String key;
  final Object? value;
}

class InjuryRiskEstimate {
  const InjuryRiskEstimate({
    required this.riskLevel,
    required this.trainingLoadScore,
    required this.checkinDate,
    this.source,
    this.loadPct,
    this.drivers,
  });

  /// 'low', 'moderate' or 'high'.
  final String riskLevel;
  final double? trainingLoadScore;
  final String checkinDate;

  /// 'model' when the scikit-learn model's score decided the estimate,
  /// 'rules' when the rules' safety floor did or no model was loaded. Null on
  /// a row saved before the service reported it.
  final String? source;

  /// The training-load index the estimate was worked out from: percent above
  /// the usual week. Null on older rows.
  final double? loadPct;

  /// Up to three inputs that raised the estimate, most influential first.
  /// Null when the row predates drivers; empty when nothing stood out.
  final List<RiskDriver>? drivers;

  /// How far round the ring to draw: the 0-100 score itself, so a low 35
  /// sits visibly nearer moderate than a low 5 does.
  ///
  /// An estimate saved without a score falls back to a fixed share for its
  /// level, so the ring still agrees with the word under it.
  double get ringValue {
    final score = trainingLoadScore;
    if (score != null) return (score / 100).clamp(0.0, 1.0);
    return switch (riskLevel) {
      'high' => 0.9,
      'moderate' => 0.55,
      _ => 0.2,
    };
  }

  String get label => switch (riskLevel) {
    'high' => 'High',
    'moderate' => 'Moderate',
    _ => 'Low',
  };

  /// What the level means for today's training, as the line under the ring
  /// says it. Guidance, as the estimate is.
  String get levelAdvice => switch (riskLevel) {
    'high' => 'Consider a lighter day: mobility or rest.',
    'moderate' => 'Train, but go a little easier.',
    _ => 'Train as planned.',
  };

  /// The same score the other way up: 100 minus the 0-100 risk score, so
  /// high is good. Home leads with it, as the prototype and the manuscript's
  /// "recovery readiness" do; Recovery keeps the injury-risk estimate as its
  /// headline and shows this beside it.
  ///
  /// Rounded up, so it always lands on its level's side of the bands: risk
  /// is moderate from 40 and high from 70, so readiness is 61+ when low,
  /// 31-60 when moderate and 30 or under when high. Null for an estimate
  /// saved without a score -- its level still shows, but no number is
  /// invented for it.
  int? get readiness {
    final score = trainingLoadScore;
    if (score == null) return null;
    return (100 - score).ceil().clamp(0, 100);
  }

  /// The readiness card's tag, by level rather than by number, so the words
  /// never second-guess the level the ML service chose.
  String get recoveryLabel => switch (riskLevel) {
    'high' => 'Recovery low',
    'moderate' => 'Recovery fair',
    _ => 'Recovery good',
  };

  /// What today's readiness suggests. Guidance, as the estimate is.
  String get readinessHeadline => switch (riskLevel) {
    'high' => 'Consider a lighter day',
    'moderate' => 'Train, but go a little easier',
    _ => "You're primed to train",
  };

  /// "Why: you slept poorly and this week is 35% above your usual." -- the
  /// estimate's [drivers] in plain English, or null when there is nothing to
  /// say.
  ///
  /// Null for a row that predates drivers. The server fills such rows with an
  /// empty list, so a missing [source] is the tell as much as a missing list:
  /// "nothing stands out" would be a claim that estimate never made. A
  /// driver this build has no words for is skipped rather than shown raw.
  String? get whyLine {
    final drivers = this.drivers;
    if (drivers == null || source == null) return null;
    if (drivers.isEmpty) {
      return 'Nothing in your check-ins, training or history stands out.';
    }
    final phrases = [for (final d in drivers) ?_driverPhrase(d)];
    if (phrases.isEmpty) return null;
    final joined = phrases.length == 1
        ? phrases.single
        : '${phrases.sublist(0, phrases.length - 1).join(', ')} '
              'and ${phrases.last}';
    return 'Why: $joined.';
  }

  factory InjuryRiskEstimate.fromJson(Map<String, dynamic> json) =>
      InjuryRiskEstimate(
        riskLevel: json['riskLevel'] as String,
        trainingLoadScore: (json['trainingLoadScore'] as num?)?.toDouble(),
        checkinDate: json['checkinDate'] as String,
        source: json['source'] is String ? json['source'] as String : null,
        loadPct: json['loadPct'] is num
            ? (json['loadPct'] as num).toDouble()
            : null,
        drivers: _parseDrivers(json['drivers']),
      );
}

/// Older rows have no `drivers` at all, so anything that is not a list reads
/// as absent, and an entry without a string key is dropped rather than
/// failing the whole Recovery tab over one bad row.
List<RiskDriver>? _parseDrivers(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final entry in raw)
      if (entry is Map && entry['key'] is String)
        RiskDriver(key: entry['key'] as String, value: entry['value']),
  ];
}

/// The highest load index the server reports (`MAX_LOAD` in
/// server/src/db/training-load.js).
const _loadCap = 130;

/// One driver as a clause of the "Why" sentence, worded by its value where
/// that changes the meaning -- a little sore is not very sore. Every value
/// the rules give points to has words, since only those can be drivers.
String? _driverPhrase(RiskDriver driver) {
  final value = driver.value;
  switch (driver.key) {
    case 'load':
      if (value is! num) return null;
      final pct = value.round();
      // Any load above zero earns points, so a sliver still counts -- but
      // "0% above" would contradict the line it sits in.
      if (pct < 1) return 'this week is a little above your usual';
      // The server caps the index here, so a reading at the cap may stand
      // for any bigger surge.
      if (pct >= _loadCap) {
        return 'this week is at least $_loadCap% above your usual';
      }
      return 'this week is $pct% above your usual';
    case 'injury_history':
      if (value is! num || value < 1) return null;
      final n = value.round();
      return n == 1 ? 'you have a past injury' : 'you have $n past injuries';
    case 'sleep':
      return switch (value) {
        'poor' => 'you slept poorly',
        'fair' => 'you slept fairly',
        'good' => 'your sleep was good but not excellent',
        _ => null,
      };
    case 'soreness':
      return switch (value) {
        'severe' => 'your muscles are very sore',
        'moderate' => 'your muscles are sore',
        'mild' => 'your muscles are a little sore',
        _ => null,
      };
    case 'energy':
      return switch (value) {
        'very_low' => 'your energy is very low',
        'low' => 'your energy is low',
        'moderate' => 'your energy is only moderate',
        _ => null,
      };
    case 'stress':
      return switch (value) {
        'high' => 'your stress is high',
        'moderate' => 'your stress is moderate',
        'low' => 'you have a little stress',
        _ => null,
      };
    case 'recent_pain':
      return switch (value) {
        'severe' => 'you reported severe pain after a recent workout',
        'moderate' => 'you reported pain after a recent workout',
        'mild' => 'you reported mild pain after a recent workout',
        _ => null,
      };
  }
  return null;
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
