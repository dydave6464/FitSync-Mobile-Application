/// The few body areas a person thinks in, over the catalogue's nineteen
/// muscle groups.
///
/// The library's muscle buttons filter by these, and a hand-picked workout is
/// named by them ("Chest & Back workout"), so the two always agree on what
/// "Back" covers. The order is the order the buttons appear in, and breaks
/// ties when a workout is named.
enum MuscleRegion {
  chest('Chest', ['pectorals', 'serratus anterior']),
  back('Back', ['upper back', 'lats', 'traps', 'spine', 'levator scapulae']),
  legs('Legs', [
    'glutes',
    'quads',
    'hamstrings',
    'calves',
    'adductors',
    'abductors',
  ]),
  shoulders('Shoulders', ['delts']),
  arms('Arms', ['biceps', 'triceps', 'forearms']),
  core('Core', ['abs']),
  cardio('Cardio', ['cardiovascular system']);

  const MuscleRegion(this.label, this.muscleGroups);

  final String label;

  /// The `muscle_group` values this area covers, exactly as the server
  /// stores them (`server/src/db/seeds/exercises.json`).
  final List<String> muscleGroups;

  /// The areas a session counts as upper body, for naming one that works
  /// several of them.
  static const upperBody = {chest, back, shoulders, arms};
}

/// The area [muscleGroup] belongs to, or null for a value this list does not
/// know -- which is then left out rather than guessed at.
MuscleRegion? regionOf(String muscleGroup) {
  for (final region in MuscleRegion.values) {
    if (region.muscleGroups.contains(muscleGroup)) return region;
  }
  return null;
}

/// The areas [muscleGroups] work, the busiest first; a tie keeps the areas'
/// usual order. A muscle group this does not know is left out.
List<MuscleRegion> regionsByCount(Iterable<String> muscleGroups) {
  final counts = <MuscleRegion, int>{};
  for (final muscle in muscleGroups) {
    final region = regionOf(muscle);
    if (region != null) counts[region] = (counts[region] ?? 0) + 1;
  }
  return counts.keys.toList()..sort((a, b) {
    final byCount = counts[b]!.compareTo(counts[a]!);
    return byCount != 0 ? byCount : a.index.compareTo(b.index);
  });
}

/// What to call a hand-picked workout, from its exercises' muscle groups.
///
/// One or two areas are named, the busier first: "Chest & Arms workout".
/// Three or more read as "Upper body workout" when they all are, and "Full
/// body workout" otherwise -- a list of four areas is not a name.
///
/// Null when nothing in [muscleGroups] is an area this knows, for the caller
/// to fall back on its own wording.
String? manualWorkoutName(Iterable<String> muscleGroups) {
  final regions = regionsByCount(muscleGroups);
  if (regions.isEmpty) return null;

  return switch (regions) {
    [final only] => '${only.label} workout',
    [final first, final second] => '${first.label} & ${second.label} workout',
    _ when regions.every(MuscleRegion.upperBody.contains) =>
      'Upper body workout',
    _ => 'Full body workout',
  };
}
