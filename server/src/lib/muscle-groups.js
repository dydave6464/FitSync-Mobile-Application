'use strict';

/// The six groups Recovery's "Last trained" card shows, in body order -- the
/// order used for untrained groups and to break ties.
const GROUPS = ['chest', 'back', 'shoulders', 'arms', 'legs', 'core'];

/// The catalogue's muscle_group values (what a movement TRAINS, see migration
/// 009) folded into those groups. The catalogue speaks anatomy -- "lats",
/// "serratus anterior" -- which a person scanning Recovery does not.
const GROUP_OF = {
  pectorals: 'chest',
  'serratus anterior': 'chest',
  'upper back': 'back',
  lats: 'back',
  traps: 'back',
  spine: 'back',
  'levator scapulae': 'back',
  delts: 'shoulders',
  biceps: 'arms',
  triceps: 'arms',
  forearms: 'arms',
  quads: 'legs',
  hamstrings: 'legs',
  glutes: 'legs',
  calves: 'legs',
  adductors: 'legs',
  abductors: 'legs',
  abs: 'core',
};

/// The group [muscle] belongs to, or null for a muscle outside the map --
/// left off the card rather than guessed at.
function groupOf(muscle) {
  return Object.hasOwn(GROUP_OF, muscle) ? GROUP_OF[muscle] : null;
}

module.exports = { GROUPS, groupOf };
