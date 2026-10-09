'use strict';
const { loadsRegion } = require('./injury-muscle-groups');

// Recorded as the reason when nothing more specific applies: the exercise
// trains a muscle group belonging to the injured region, but no contraindication
// names it. Distinct from a `pattern` string, which always comes from the
// contraindication table.
const REGION_REASON = 'trains_region';

/// Picks the one injury an exercise's cues are written for, from the rows of
/// that exercise in ascending injury_id order. Two passes rather than one
/// ORDER BY: "any contraindication beats any overlap" would be a CASE the next
/// reader has to decode. The first match in each pass is the lowest id --
/// arbitrary, but stable, which is what the cache key needs.
function pick(rows) {
  const contraindicated = rows.find((row) => row.pattern !== null);
  if (contraindicated) {
    return {
      injuryId: contraindicated.injury_id,
      injuryName: contraindicated.name,
      reason: contraindicated.pattern,
    };
  }
  const overlapping = rows.find((row) => loadsRegion(row.region_group, row.muscle_group));
  if (overlapping) {
    return {
      injuryId: overlapping.injury_id,
      injuryName: overlapping.name,
      reason: REGION_REASON,
    };
  }
  return null;
}

/// flagFor for a whole list in one query: the plan and session payloads tag
/// every row, and the tag must mean exactly "this exercise gets AI cues".
///
/// Returns a map, empty for an exercise with no injuries, or none it
/// touches -- the common case, and the one that has to cost nothing. An
/// exercise absent from the map means the catalogue's own cues are the
/// whole answer, and no service is called for it.
///
/// Two conditions flag, and both are needed because they fire in different
/// flows. A GENERATED plan trips the second only: the generator excludes
/// contraindicated exercises outright (`ml/app/catalogue.py`) and keeps the
/// rest of the injured area (`ml/app/main.py`), so an injured user's plan
/// keeps coached work around the injury. A HAND-PICKED session has no such
/// filter and can contain an outright contraindicated exercise.
///
/// Exactly one injury is chosen even when several match, because the cache is
/// keyed on one injury_id: a squat flagging for both a knee and a lower back
/// must resolve to the same row on every request, or it writes two.
async function flagsFor(pool, userId, exerciseIds) {
  const ids = [...new Set(exerciseIds)];
  const flags = new Map();
  if (ids.length === 0) return flags;

  const [rows] = await pool.query(
    `SELECT e.exercise_id, i.injury_id, i.name, i.region_group, e.muscle_group, c.pattern
       FROM user_injuries ui
       JOIN injuries i ON i.injury_id = ui.injury_id
       JOIN exercises e ON e.exercise_id IN (?)
       LEFT JOIN exercise_contraindications c
         ON c.exercise_id = e.exercise_id AND c.injury_id = i.injury_id
      WHERE ui.user_id = ?
      ORDER BY e.exercise_id ASC, i.injury_id ASC`,
    [ids, userId],
  );

  const byExercise = new Map();
  for (const row of rows) {
    if (!byExercise.has(row.exercise_id)) byExercise.set(row.exercise_id, []);
    byExercise.get(row.exercise_id).push(row);
  }
  for (const [exerciseId, exerciseRows] of byExercise) {
    const flag = pick(exerciseRows);
    if (flag) flags.set(exerciseId, flag);
  }
  return flags;
}

/// Whether this exercise warrants cues written for an injury, and which one.
/// Null when the user has no injuries or none this exercise touches.
async function flagFor(pool, userId, exerciseId) {
  return (await flagsFor(pool, userId, [exerciseId])).get(exerciseId) ?? null;
}

/// The `coaching` field an exercise carries in plan and session payloads.
function toCoaching(flag) {
  return flag ? { injuryId: flag.injuryId, injuryName: flag.injuryName } : null;
}

module.exports = { flagFor, flagsFor, toCoaching, REGION_REASON };
