class VolumeBucket {
  const VolumeBucket({required this.label, required this.volumeKg});
  final String label;
  final double volumeKg;

  factory VolumeBucket.fromJson(Map<String, dynamic> json) => VolumeBucket(
        label: json['label'] as String,
        volumeKg: (json['volumeKg'] as num).toDouble(),
      );
}

/// Sessions completed against what the active plan asked for.
///
/// The hero stat, because it is the one a beginner can act on and the only one
/// that means anything in week one -- every trend chart is still a single
/// point then.
class Adherence {
  const Adherence({required this.done, required this.target, required this.weeks});

  final int done;

  /// Null when there is no active plan. The plan is what defines a target, and
  /// one invented without it would be fiction, so the card shows the count
  /// alone rather than a denominator nobody agreed to.
  final int? target;

  final int weeks;

  bool get hasTarget => target != null && target! > 0;
  String get label => hasTarget ? '$done / $target' : '$done';
  double get fraction => hasTarget ? (done / target!).clamp(0, 1) : 0;

  factory Adherence.fromJson(Map<String, dynamic> json) => Adherence(
        done: json['done'] as int,
        target: json['target'] as int?,
        weeks: json['weeks'] as int,
      );
}

/// This window's volume against the one before it.
class VolumeChange {
  const VolumeChange({
    required this.totalKg,
    required this.previousKg,
    required this.changePct,
  });

  final double totalKg;
  final double previousKg;

  /// Null when the previous window held nothing — a first week has nothing to
  /// be up against, and a percentage measured from zero is not a fact.
  final int? changePct;

  bool get hasChange => changePct != null;
  String get label => changePct == null
      ? ''
      : '${changePct! >= 0 ? '+' : ''}$changePct%';

  factory VolumeChange.fromJson(Map<String, dynamic> json) => VolumeChange(
        totalKg: (json['totalKg'] as num).toDouble(),
        previousKg: (json['previousKg'] as num).toDouble(),
        changePct: json['changePct'] as int?,
      );
}

class MuscleSets {
  const MuscleSets({required this.muscle, required this.sets});
  final String muscle;
  final int sets;

  factory MuscleSets.fromJson(Map<String, dynamic> json) => MuscleSets(
        muscle: json['muscle'] as String,
        sets: json['sets'] as int,
      );
}

class TrainingAnalytics {
  const TrainingAnalytics({
    required this.period,
    required this.volume,
    required this.change,
    required this.adherence,
    required this.muscles,
  });

  final String period;
  final List<VolumeBucket> volume;
  final VolumeChange change;
  final Adherence adherence;
  final List<MuscleSets> muscles;

  /// Bars are relative to the biggest group, not to a target. A per-muscle
  /// weekly target is a claim about training science this app is not in a
  /// position to make.
  double muscleFraction(MuscleSets row) {
    if (muscles.isEmpty) return 0;
    final top = muscles.first.sets;
    return top == 0 ? 0 : row.sets / top;
  }

  factory TrainingAnalytics.fromJson(Map<String, dynamic> json) => TrainingAnalytics(
        period: json['period'] as String,
        volume: [
          for (final b in (json['volume'] as List<dynamic>? ?? const []))
            VolumeBucket.fromJson(b as Map<String, dynamic>),
        ],
        change: VolumeChange.fromJson(json['change'] as Map<String, dynamic>),
        adherence: Adherence.fromJson(json['adherence'] as Map<String, dynamic>),
        muscles: [
          for (final m in (json['muscles'] as List<dynamic>? ?? const []))
            MuscleSets.fromJson(m as Map<String, dynamic>),
        ],
      );
}
