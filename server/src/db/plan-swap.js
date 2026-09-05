'use strict';
const AppError = require('../lib/app-error');

// Candidate rules mirror ml/app/catalogue.py. An alternative the generator
// would never have been allowed to pick is not a legitimate substitute, so the
// filters are deliberately the same ones: owned equipment (walking
// parent_equipment_id), no contraindication for a reported injury, and
// strength only. Equipment is reported in the *curated* vocabulary, matching
// src/db/plans.js -- never the raw tag src/db/exercises.js returns.

const BODY_WEIGHT = 'body weight';

async function loadSwapContext(pool, userId, planExerciseId) {
  const [rows] = await pool.query(
    // savePlan sets is_active = FALSE on a user's previous plan rather than
    // deleting it, so a superseded plan's rows survive indefinitely. Without
    // this clause a client still holding ids from an old plan -- e.g. after
    // POST /profile/complete-onboarding is re-issued -- could PATCH a swap
    // onto a plan that is no longer the user's active one.
    `SELECT pe.plan_exercise_id, pe.plan_id, pe.exercise_id, x.muscle_group
       FROM plan_exercises pe
       JOIN workout_plans wp ON wp.plan_id = pe.plan_id
       JOIN exercises x ON x.exercise_id = pe.exercise_id
      WHERE pe.plan_exercise_id = ? AND wp.user_id = ? AND wp.is_active = TRUE`,
    [planExerciseId, userId],
  );
  // Null, not throw: the route turns this into a 404 so a probe cannot tell
  // "no such row" apart from "not yours".
  if (rows.length === 0) return null;
  const row = rows[0];

  const [owned] = await pool.query(
    `SELECT equipment_id FROM user_equipment WHERE user_id = ?`, [userId],
  );
  const [bw] = await pool.query(
    'SELECT equipment_id FROM equipment WHERE name = ?', [BODY_WEIGHT],
  );
  const selectedIds = owned.map((r) => r.equipment_id);
  // Body weight is always available, exactly as main.py unions it in before
  // calling fetch_candidates.
  const ownedIds = [...new Set([...selectedIds, ...bw.map((r) => r.equipment_id)])];

  const [injuries] = await pool.query(
    'SELECT injury_id FROM user_injuries WHERE user_id = ?', [userId],
  );
  const [inPlan] = await pool.query(
    'SELECT exercise_id FROM plan_exercises WHERE plan_id = ?', [row.plan_id],
  );

  return {
    planId: row.plan_id,
    planExerciseId: row.plan_exercise_id,
    exerciseId: row.exercise_id,
    muscleGroup: row.muscle_group,
    ownedIds,
    selectedIds,
    injuryIds: injuries.map((r) => r.injury_id),
    inPlanIds: inPlan.map((r) => r.exercise_id),
  };
}

function safetyClauses(ctx, params, eligibleIds) {
  let sql = `
     WHERE x.status = 'live'
       AND COALESCE(cat.category, 'strength') = 'strength'
       AND COALESCE(eq.parent_equipment_id, eq.equipment_id) IN (?)
       AND NOT EXISTS (
             SELECT 1 FROM exercise_equipment_requirements r
              WHERE r.exercise_id = x.exercise_id AND r.equipment_id NOT IN (?)
           )
       AND x.exercise_id NOT IN (?)`;
  // Requirements stay against ownedIds: classifyRequirements only ever emits
  // 'bench' and 'pull-up bar', never body weight, so this list is already
  // effectively the user's own selection -- narrowing it would change nothing
  // except to make that non-obvious.
  params.push(eligibleIds, ctx.ownedIds, ctx.inPlanIds);

  if (ctx.injuryIds.length > 0) {
    sql += `
       AND NOT EXISTS (
             SELECT 1 FROM exercise_contraindications c
              WHERE c.exercise_id = x.exercise_id AND c.injury_id IN (?)
           )`;
    params.push(ctx.injuryIds);
  }
  return sql;
}

/// Body weight is offered only where the user's own equipment cannot train
/// the muscle group at all.
///
/// The union of selected equipment and body weight is what makes onboarding
/// survivable -- a user who ticks only Bench, a curated chip with no exercises
/// tagged to it, must still get a plan. But applied to every list it reads as
/// the app ignoring the answer: five of the catalogue's muscle groups (lats,
/// abductors, adductors, spine, levator scapulae) have no dumbbell exercise,
/// while pectorals, delts, biceps and triceps have dozens, and a dumbbell
/// owner was offered push-ups in all of them. Ordering alone did not fix that:
/// a list whose first screen is dumbbells and whose second is body weight
/// still looks like a list of push-ups.
///
/// So: ask for the user's own equipment first, and fall back to the union only
/// when that returns nothing. The fallback is what keeps a lats row from being
/// a dead end.
async function listAlternatives(pool, ctx, { q = null, limit = 20, bodyweightOnly = false } = {}) {
  // bodyweightOnly asks for the opposite of strictness, so it skips the strict
  // pass entirely. Nothing in the app sends it any more; the parameter and its
  // test remain because the endpoint's contract is public.
  if (!bodyweightOnly && ctx.selectedIds.length > 0) {
    const strict = await queryAlternatives(
      pool, ctx, ctx.selectedIds, { q, limit, bodyweightOnly },
    );
    if (strict.length > 0) return strict;
  }
  return queryAlternatives(pool, ctx, ctx.ownedIds, { q, limit, bodyweightOnly });
}

async function queryAlternatives(pool, ctx, eligibleIds, { q, limit, bodyweightOnly }) {
  const params = [];
  let sql = `
    SELECT x.exercise_id, x.name, x.muscle_group, x.thumbnail_url,
           COALESCE(parent.display_name, eq.display_name, eq.name) AS equipment
      FROM exercises x
      LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id
      LEFT JOIN equipment parent ON parent.equipment_id = eq.parent_equipment_id
      LEFT JOIN exercise_categories cat ON cat.exercise_id = x.exercise_id`;

  sql += safetyClauses(ctx, params, eligibleIds);

  if (q) {
    // Search spans every muscle group: a gym missing a machine may call for a
    // different movement entirely. Only the muscle filter is relaxed.
    sql += ' AND x.name LIKE ?';
    params.push(`%${q}%`);
  } else {
    sql += ' AND x.muscle_group = ?';
    params.push(ctx.muscleGroup);
  }

  if (bodyweightOnly) {
    // eq.name is the raw catalogue tag here, which is the right vocabulary for
    // this join -- the curated display name is only computed for output.
    sql += ' AND eq.name = ?';
    params.push(BODY_WEIGHT);
  }

  // Equipment the user actually selected outranks the body-weight fallback,
  // mirroring _PREFER_SELECTED: without it body weight's low ids dominate and
  // a dumbbell owner is offered push-ups. A curated preference tier, when it
  // exists, becomes the first key here and demotes these two.
  sql += `
     ORDER BY CASE WHEN COALESCE(eq.parent_equipment_id, eq.equipment_id) IN (?)
                   THEN 0 ELSE 1 END,
              x.exercise_id ASC
     LIMIT ?`;
  params.push(ctx.selectedIds.length > 0 ? ctx.selectedIds : [0], limit);

  const [rows] = await pool.query(sql, params);
  return rows.map((r) => ({
    exerciseId: r.exercise_id,
    name: r.name,
    muscleGroup: r.muscle_group,
    equipment: r.equipment,
    thumbnailUrl: r.thumbnail_url,
  }));
}

// Re-derived server-side rather than trusting the sheet: a stale client could
// otherwise write an exercise that has since been depromoted or ruled out.
async function isAllowedTarget(pool, ctx, exerciseId) {
  const params = [];
  let sql = `
    SELECT x.exercise_id
      FROM exercises x
      LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id
      LEFT JOIN exercise_categories cat ON cat.exercise_id = x.exercise_id`;
  // Permissive on purpose: the list is strict, but a target that a slightly
  // stale sheet still offers -- or one the fallback legitimately produced --
  // must not be refused for equipment reasons it cannot see.
  sql += safetyClauses(ctx, params, ctx.ownedIds);
  sql += ' AND x.exercise_id = ? LIMIT 1';
  params.push(exerciseId);

  const [rows] = await pool.query(sql, params);
  return rows.length === 1;
}

async function swapPlanExercise(pool, ctx, exerciseId) {
  if (!(await isAllowedTarget(pool, ctx, exerciseId))) {
    throw AppError.badRequest(
      'EXERCISE_NOT_ALLOWED',
      'That exercise is not available for this plan.',
    );
  }
  // order_no, target_sets and target_reps are deliberately untouched: volume
  // comes from the user's goal (ml/app/rules/parameters.py), not the exercise.
  await pool.query(
    'UPDATE plan_exercises SET exercise_id = ? WHERE plan_exercise_id = ?',
    [exerciseId, ctx.planExerciseId],
  );
}

module.exports = { loadSwapContext, listAlternatives, swapPlanExercise };
