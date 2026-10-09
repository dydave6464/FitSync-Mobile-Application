'use strict';

// The server's own region map for the cue gate (`./cue-gate.js`): which
// plan and session exercises get AI cues and the "AI coached" tag. An
// exercise with no direct contraindication still flags when it loads a
// muscle group belonging to a region the user reported injured.
//
// The plan generator (`ml/app/main.py`) no longer excludes by region at
// all -- it removes only what `exercise_contraindications` names for an
// injury -- so there is nothing on that side to keep this in sync with.
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
