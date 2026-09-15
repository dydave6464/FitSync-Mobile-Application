'use strict';

// A port of INJURY_MUSCLE_GROUPS in `ml/app/schemas.py`. The plan generator
// applies it in Python to EXCLUDE exercises; anything here applies it to decide
// whether a movement loads a region the user has reported injured — the
// opposite decision from the same fact.
//
// Duplicated rather than fetched: the ML service is optional (ML_MODE=stub is
// the default) and this must work when it is not running at all. Keep the two
// in sync — a region added there and not here goes unnoticed on this side.
const INJURY_MUSCLE_GROUPS = {
  upper_body: ['delts', 'pectorals', 'triceps', 'biceps', 'forearms', 'lats', 'upper back', 'traps'],
  back_core: ['spine', 'abs', 'upper back', 'traps', 'levator scapulae'],
  lower_body: ['quads', 'hamstrings', 'glutes', 'calves', 'adductors', 'abductors'],
};

/// Whether this muscle group is one the given region group covers.
function loadsRegion(regionGroup, muscleGroup) {
  const groups = INJURY_MUSCLE_GROUPS[regionGroup] || [];
  return groups.includes(String(muscleGroup || '').toLowerCase());
}

module.exports = { INJURY_MUSCLE_GROUPS, loadsRegion };
