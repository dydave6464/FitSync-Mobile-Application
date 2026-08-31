import '../../plans/domain/workout_plan.dart';

/// MET values for resistance training, from the Compendium of Physical
/// Activities, keyed on the curated equipment names the server resolves.
///
/// These are population averages for an activity type, not a measurement of
/// this user doing this exercise. Rest length, load and effort dominate real
/// energy cost and none of them is recorded, which is why the result is
/// rendered with a leading "~" and why there is no per-exercise breakdown.
const _mets = <String, double>{
  'Barbell': 5.0,
  'Machines': 5.0,
  'Dumbbells': 5.0,
  'Kettlebell': 5.0,
  'Bodyweight': 4.0,
  'Bands': 3.5,
};

/// The mid value, so an equipment name this table has never heard of cannot
/// skew the estimate in either direction.
const _defaultMet = 4.0;

/// Approximate energy for one session of [plan], or null when it cannot be
/// estimated honestly.
///
/// Null rather than a guess when [weightKg] is unknown: body weight is
/// skippable during onboarding, and substituting a population average would
/// produce a confident-looking figure derived from a stranger's body.
int? estimateSessionKcal({required WorkoutPlan plan, required double? weightKg}) {
  if (weightKg == null || plan.exercises.isEmpty) return null;

  // Equal weighting: per-exercise duration is not recorded, only sets and
  // reps, which do not give time.
  final total = plan.exercises
      .map((e) => _mets[e.equipment] ?? _defaultMet)
      .reduce((a, b) => a + b);
  final met = total / plan.exercises.length;

  return (met * weightKg * (plan.sessionLengthMin / 60)).round();
}
