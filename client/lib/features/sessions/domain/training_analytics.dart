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

/// Kilograms lifted for one muscle group in the window.
///
/// Volume rather than a set count: five sets of 20 kg and five of 100 kg
/// draw the same bar under a count, which says nothing about the work done.
/// The server's measure is `SUM(weight_kg * reps)`, the same one
/// `total_volume_kg` carries per session -- so this card and the volume
/// trend above it cannot disagree about what a kilogram of work is.
class MuscleVolume {
  const MuscleVolume({required this.muscle, required this.volumeKg});
  final String muscle;
  final double volumeKg;

  factory MuscleVolume.fromJson(Map<String, dynamic> json) => MuscleVolume(
        muscle: json['muscle'] as String,
        // `as double?` would throw on a whole number: jsonDecode gives 600 as
        // an int. Same reasoning as LoggedSet.weightKg.
        volumeKg: (json['volumeKg'] as num).toDouble(),
      );
}

class TrainingAnalytics {
  const TrainingAnalytics({
    required this.period,
    required this.volume,
    required this.change,
    required this.adherence,
    required this.muscles,
    this.musclesLocked = false,
  });

  final String period;
  final List<VolumeBucket> volume;
  final VolumeChange change;
  final Adherence adherence;
  final List<MuscleVolume> muscles;

  /// Why [muscles] is empty: this is a Pro card and the user is not on Pro,
  /// so the server sent no numbers at all.
  ///
  /// A Pro user who has logged nothing weighted also gets an empty list, and
  /// the card reads differently for each -- one offers an upgrade, the other
  /// explains that bodyweight work carries no volume. Defaults to false so a
  /// payload from before the field reads as "not locked", which is what a
  /// server that never gated this meant.
  final bool musclesLocked;

  /// Bars are relative to the biggest group, not to a target. A per-muscle
  /// weekly target is a claim about training science this app is not in a
  /// position to make.
  double muscleFraction(MuscleVolume row) {
    if (muscles.isEmpty) return 0;
    final top = muscles.first.volumeKg;
    return top == 0 ? 0 : row.volumeKg / top;
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
            MuscleVolume.fromJson(m as Map<String, dynamic>),
        ],
        musclesLocked: json['musclesLocked'] as bool? ?? false,
      );
}
