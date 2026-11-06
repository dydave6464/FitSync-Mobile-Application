/// How an exercise's name, muscle and equipment read on screen.
///
/// The catalogue stores all three in lowercase, as its source dataset did
/// ('barbell bench press', 'pectorals', 'body weight'), and the server sends
/// them as stored. Shown raw, the same equipment read 'Bodyweight' on the
/// library's filter and 'body weight' on the row beneath it, and anatomy
/// jargon stood where the muscle buttons say 'Chest'. Display only: filters,
/// icons and requests keep the stored values.
library;

/// [name] with its first letter capitalised; the rest is left as the
/// catalogue has it, so 'DB' or '3/4' are never mangled.
String exerciseDisplayName(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

/// The everyday word for a stored muscle group: the muscle buttons' own word
/// where one covers it ('Chest', 'Shoulders'), a short plain name otherwise.
/// A value this does not know is capitalised rather than dropped.
String muscleLabel(String muscleGroup) =>
    _muscles[muscleGroup] ?? exerciseDisplayName(muscleGroup);

/// The library filter's word for a stored equipment value ('Bodyweight',
/// 'Dumbbells'), or the value capitalised. A curated name, as the plan path
/// sends, comes back as it was.
String equipmentLabel(String equipment) =>
    _equipment[equipment] ?? exerciseDisplayName(equipment);

const _muscles = {
  'pectorals': 'Chest',
  'delts': 'Shoulders',
  'cardiovascular system': 'Cardio',
  'serratus anterior': 'Serratus',
  'levator scapulae': 'Neck',
  'spine': 'Lower back',
};

/// The filter's chips (server/src/db/seed-equipment.js), plus the one
/// abbreviation a capital alone would get wrong.
const _equipment = {
  'body weight': 'Bodyweight',
  'dumbbell': 'Dumbbells',
  'band': 'Bands',
  'ez barbell': 'EZ barbell',
};
