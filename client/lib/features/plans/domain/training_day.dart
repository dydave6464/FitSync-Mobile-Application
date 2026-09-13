/// One day's worth of training, and the muscle groups it covers.
///
/// The unit a single workout is chosen against. A *split* is a rotation of
/// days, so filtering a catalogue by a whole split barely filters: measured
/// against the live catalogue, push_pull_legs covered 997 of 1,203 exercises
/// and upper_lower covered the identical set -- two controls that looked
/// different and behaved the same. One day is 422.
///
/// The groups are mirrored from `ml/app/rules/splits.py`, which is the
/// service's own definition and the one a generated plan is built from.
/// Mirrored rather than fetched because nothing serves them; a change there
/// needs a change here, which is why the values are spelled out rather than
/// derived.
class TrainingDay {
  const TrainingDay({required this.label, required this.muscleGroups});

  final String label;

  /// The catalogue's `muscle_group` values this day draws from. Empty means
  /// no filter at all -- splits.py gives the same shape the same meaning:
  /// "Empty means no filter at all: every group is eligible. That is full
  /// body."
  final List<String> muscleGroups;
}

const _push = ['pectorals', 'delts', 'triceps'];
const _pull = ['lats', 'upper back', 'biceps', 'traps'];
const _legs = ['quads', 'glutes', 'hamstrings', 'calves', 'adductors', 'abductors'];

/// Every distinct day the four splits divide a week into.
///
/// upper_lower's "Lower" is push_pull_legs' "Legs" -- the same groups under
/// two names -- so it appears once. Offering both would be two chips that
/// filter identically, which is the problem this list exists to avoid.
const trainingDays = <TrainingDay>[
  TrainingDay(label: 'Full body', muscleGroups: []),
  TrainingDay(label: 'Upper body', muscleGroups: [..._push, ..._pull]),
  TrainingDay(label: 'Push', muscleGroups: _push),
  TrainingDay(label: 'Pull', muscleGroups: _pull),
  TrainingDay(label: 'Legs', muscleGroups: _legs),
  TrainingDay(label: 'Cardio & core', muscleGroups: ['cardiovascular system', 'abs']),
];
