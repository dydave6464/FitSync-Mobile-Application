'use strict';
const AppError = require('../lib/app-error');

// Day names are derived from the split style rather than stored, because
// nothing lets anyone type one: generated and custom plans both PICK a split,
// and the split is what names its days. See the design, sections 3 and 4.
//
// This must agree with ml/app/rules/splits.py, which decides day 2 is a pull
// day by the muscles it draws from. Two services in different languages that
// cannot share code, so the agreement is pinned by a test asserting day 1 of a
// push_pull_legs plan holds push MUSCLES -- not merely that a day 1 exists.
const SPLIT_DAY_NAMES = {
  full_body: ['Full body'],
  push_pull_legs: ['Push', 'Pull', 'Legs'],
  upper_lower: ['Upper', 'Lower'],
  cardio_core: ['Cardio & core'],
};

function dayNamesFor(splitStyle) {
  return SPLIT_DAY_NAMES[splitStyle] || SPLIT_DAY_NAMES.full_body;
}

// The ML service names exercises; plan_exercises needs ids, and the column is
// NOT NULL with a foreign key. Everything here exists to bridge that gap
// safely — see the spec, section 6.
async function resolveExerciseIds(pool, names) {
  const map = new Map();
  if (names.length === 0) return map;

  const [rows] = await pool.query(
    `SELECT exercise_id, name FROM exercises
      WHERE status = 'live' AND LOWER(name) IN (?)
      ORDER BY exercise_id ASC`,
    [names.map((n) => String(n).toLowerCase())],
  );

  // The catalogue has known duplicate names — the earlier catalogue slice
  // recorded six of them — so more than one live row can share a name.
  // ORDER BY exercise_id ASC plus first-write-wins below means a duplicate
  // always resolves to its lowest exercise_id, matching the same
  // exercise_id tiebreaker the catalogue's own paginated query already uses
  // (see src/db/exercises.js), rather than whatever order MySQL happens to
  // return. Without this, two users onboarding with the same generated plan
  // could silently land on different exercises for the same name.
  const byLower = new Map();
  for (const r of rows) {
    const key = r.name.toLowerCase();
    if (!byLower.has(key)) byLower.set(key, r.exercise_id);
  }
  for (const name of names) {
    const id = byLower.get(String(name).toLowerCase());
    if (id) map.set(name, id);
  }
  return map;
}

async function savePlan(pool, userId, plan) {
  const names = plan.exercises.map((e) => e.name);
  const resolved = await resolveExerciseIds(pool, names);

  const unresolved = names.filter((n) => !resolved.has(n));
  if (unresolved.length > 0) {
    // Fail loudly. A plan that silently drops exercises looks like a working
    // feature producing bad advice, which is worse than an error.
    throw new AppError(
      502,
      'PLAN_GENERATION_FAILED',
      'The generated plan referenced exercises that are not in the catalogue.',
      unresolved.map((name) => ({ field: 'exercise', value: name })),
    );
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // One active plan per user. Module 2 will add history; this keeps the
    // "current plan" question unambiguous until then.
    await conn.query(
      'UPDATE workout_plans SET is_active = FALSE WHERE user_id = ?', [userId],
    );
    const [result] = await conn.query(
      `INSERT INTO workout_plans
         (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
       VALUES (?, ?, ?, ?, ?, ?, TRUE)`,
      [userId, plan.name, plan.splitStyle, plan.daysPerWeek, plan.sessionLengthMin, plan.weekNo || 1],
    );
    for (const ex of plan.exercises) {
      await conn.query(
        `INSERT INTO plan_exercises (plan_id, exercise_id, day_no, order_no, target_sets, target_reps)
         VALUES (?, ?, ?, ?, ?, ?)`,
        // A generator that sends no dayNo is a one-day plan, which is what
        // every plan was before migration 013.
        [result.insertId, resolved.get(ex.name), ex.dayNo || 1, ex.orderNo, ex.targetSets, ex.targetReps],
      );
    }
    await conn.commit();
    return result.insertId;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

async function getActivePlan(pool, userId) {
  const [plans] = await pool.query(
    `SELECT plan_id, name, split_style, days_per_week, session_length_min, week_no, created_at
       FROM workout_plans WHERE user_id = ? AND is_active = TRUE
      ORDER BY plan_id DESC LIMIT 1`, [userId],
  );
  if (plans.length === 0) return null;
  const p = plans[0];

  const [exercises] = await pool.query(
    // LEFT JOINs throughout: exercises.equipment_id is nullable, and a tag
    // that was never adopted has no parent. COALESCE walks curated parent ->
    // curated self -> raw tag, so an adopted child like 'cable' reports
    // 'Machines' while an unadopted tag still reports something usable.
    //
    // This `equipment` is therefore a *curated* display name (e.g.
    // 'Bodyweight'), a different vocabulary from the raw catalogue tag (e.g.
    // 'body weight') that `GET /exercises` returns from src/db/exercises.js.
    // The client's plan_energy.dart MET table keys on this curated name.
    // Nothing today joins the two vocabularies for the same exercise, but a
    // future feature that tried — e.g. "browse the catalogue for this plan
    // exercise's equipment" — would silently return no results comparing
    // one against the other.
    `SELECT pe.plan_exercise_id, pe.day_no, pe.order_no, pe.target_sets, pe.target_reps,
            x.exercise_id, x.name, x.muscle_group, x.thumbnail_url,
            COALESCE(parent.display_name, eq.display_name, eq.name) AS equipment
       FROM plan_exercises pe
       JOIN exercises x ON x.exercise_id = pe.exercise_id
       LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id
       LEFT JOIN equipment parent ON parent.equipment_id = eq.parent_equipment_id
      WHERE pe.plan_id = ? ORDER BY pe.day_no, pe.order_no`, [p.plan_id],
  );

  return {
    planId: p.plan_id,
    name: p.name,
    splitStyle: p.split_style,
    daysPerWeek: p.days_per_week,
    sessionLengthMin: p.session_length_min,
    weekNo: p.week_no,
    // The full rotation, not merely the days that have exercises: a day that
    // came back empty is still a day of the plan, and the Plan tab needs to
    // name it rather than silently renumbering the ones that survived.
    days: dayNamesFor(p.split_style).map((name, index) => ({ dayNo: index + 1, name })),
    exercises: exercises.map((e) => ({
      planExerciseId: e.plan_exercise_id,
      exerciseId: e.exercise_id,
      name: e.name,
      muscleGroup: e.muscle_group,
      thumbnailUrl: e.thumbnail_url,
      dayNo: e.day_no,
      orderNo: e.order_no,
      targetSets: e.target_sets,
      targetReps: e.target_reps,
      equipment: e.equipment,
    })),
  };
}

module.exports = { resolveExerciseIds, savePlan, getActivePlan, dayNamesFor };
