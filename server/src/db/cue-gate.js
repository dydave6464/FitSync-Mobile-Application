'use strict';
const { loadsRegion } = require('./injury-muscle-groups');

// Recorded as the reason when nothing more specific applies: the exercise
// trains a muscle group belonging to the injured region, but no contraindication
// names it. Distinct from a `pattern` string, which always comes from the
// contraindication table.
const REGION_REASON = 'trains_region';

/// Whether this exercise warrants cues written for an injury, and which one.
///
/// Returns null when the user has no injuries, or none this exercise touches --
/// the common case, and the one that has to cost nothing. A null answer means
/// the catalogue's own cues are the whole answer, and no service is called.
///
/// Two conditions flag, and both are needed because they fire in different
/// flows. A GENERATED plan can only ever trip the second: the generator
/// excludes contraindicated exercises outright (`ml/app/catalogue.py`), but
/// relaxes its muscle-group filter when strict exclusion would leave too few
/// candidates (`ml/app/main.py`), so an injured user's plan keeps work around
/// the injury. A HAND-PICKED session has no such filter and can contain an
/// outright contraindicated exercise.
///
/// Exactly one injury is chosen even when several match, because the cache is
/// keyed on one injury_id: a squat flagging for both a knee and a lower back
/// must resolve to the same row on every request, or it writes two.
async function flagFor(pool, userId, exerciseId) {
  const [rows] = await pool.query(
    `SELECT i.injury_id, i.name, i.region_group, e.muscle_group, c.pattern
       FROM user_injuries ui
       JOIN injuries i ON i.injury_id = ui.injury_id
       JOIN exercises e ON e.exercise_id = ?
       LEFT JOIN exercise_contraindications c
         ON c.exercise_id = e.exercise_id AND c.injury_id = i.injury_id
      WHERE ui.user_id = ?
      ORDER BY i.injury_id ASC`,
    [exerciseId, userId],
  );
  // No injuries, or no such exercise -- the join drops everything either way.
  if (rows.length === 0) return null;

  // Two passes rather than one ORDER BY. The ranking is "any contraindication
  // beats any overlap", which SQL would express as a CASE the next reader has
  // to decode. Rows arrive ascending by injury_id, so the first match in each
  // pass is the lowest id -- arbitrary, but stable, which is what the cache
  // key needs.
  const contraindicated = rows.find((row) => row.pattern !== null);
  if (contraindicated) {
    return {
      injuryId: contraindicated.injury_id,
      injuryName: contraindicated.name,
      reason: contraindicated.pattern,
    };
  }

  const overlapping = rows.find(
    (row) => loadsRegion(row.region_group, row.muscle_group),
  );
  if (overlapping) {
    return {
      injuryId: overlapping.injury_id,
      injuryName: overlapping.name,
      reason: REGION_REASON,
    };
  }

  return null;
}

module.exports = { flagFor, REGION_REASON };
