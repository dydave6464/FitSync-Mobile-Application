'use strict';
const AppError = require('../lib/app-error');

// Day names are derived from the split style rather than stored, because
// nothing lets anyone type one: generated and custom plans both PICK a split,
// and the split is what names its days. See the design, sections 3 and 4.
//
// This is the server half of a hand-maintained contract with
// ml/app/rules/splits.py, which decides day 2 is a pull day by the muscles
// it draws from. The two services share no code, so nothing here can see
// splits.py and nothing there can see this file: each side pins its own
// literals against its own tests (this file's labels here, the muscle
// tuples in ml/tests/test_splits.py and test_contract.py on that side), and
// drift is caught only if one side is edited and the other is not -- no
// test spans both processes.
const SPLIT_DAY_NAMES = {
  full_body: ['Full body'],
  push_pull_legs: ['Push', 'Pull', 'Legs'],
  upper_lower: ['Upper', 'Lower'],
  cardio_core: ['Cardio & core'],
};

function dayNamesFor(splitStyle) {
  // .slice(): this is exported, so a caller mutating the returned array
  // must not corrupt the module-level map for every plan after it.
  return (SPLIT_DAY_NAMES[splitStyle] || SPLIT_DAY_NAMES.full_body).slice();
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
    `SELECT plan_id, name, split_style, days_per_week, session_length_min, week_no, source, created_at
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
    // The client labels a custom plan "Your plan" and warns before the
    // generator replaces one.
    source: p.source,
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

/// The label a custom plan is named after, per split style.
///
/// Not derived from the enum value: 'push_pull_legs'.split('_') gives "Push
/// Pull Legs", which is not how anybody writes it.
const SPLIT_LABELS = {
  full_body: 'Full Body',
  push_pull_legs: 'Push / Pull / Legs',
  upper_lower: 'Upper / Lower',
  cardio_core: 'Cardio / Core',
  bro_split: 'Bro Split',
};

/// The session's exercises, live ones only, in the order they were trained.
///
/// The same resolution lastCompletedWorkout performs: a hand-picked session
/// owns rows in session_exercises, a plan-backed one borrows the plan's rows
/// for the day it trained.
async function sessionExerciseIds(conn, session) {
  const [own] = await conn.query(
    `SELECT se.exercise_id
       FROM session_exercises se
       JOIN exercises x ON x.exercise_id = se.exercise_id
      WHERE se.session_id = ? AND x.status = 'live'
      ORDER BY se.order_no`,
    [session.session_id],
  );
  if (own.length > 0) return own.map((r) => r.exercise_id);
  if (session.plan_id === null) return [];

  const [fromPlan] = await conn.query(
    `SELECT pe.exercise_id
       FROM plan_exercises pe
       JOIN exercises x ON x.exercise_id = pe.exercise_id
      WHERE pe.plan_id = ? AND pe.day_no = ? AND x.status = 'live'
      ORDER BY pe.order_no`,
    [session.plan_id, session.plan_day_no ?? 1],
  );
  return fromPlan.map((r) => r.exercise_id);
}

/// The generator's own bounds, so a derived length cannot be something the
/// generator itself would have refused. Mirrors MIN_SESSION_MIN and
/// MAX_SESSION_MIN in src/routes/plans.js.
const MIN_SESSION_MIN = 20;
const MAX_SESSION_MIN = 120;

/// What the user actually did, per exercise, as a prescription.
///
/// sets is the number of sets logged. reps is the most frequently logged rep
/// value, ties broken by the higher -- a user who did 8, 10, 10 is prescribing
/// 10, and one who did 8 then 10 is more likely chasing 10 than settling for 8.
///
/// Nulls are excluded from the rep vote but still counted as sets: an AMRAP or
/// an untracked bodyweight movement happened even though nobody counted it.
/// With no usable rep at all the session_exercises default stands in, because
/// "null reps" is not something the logger can render.
async function prescriptionFromLogs(conn, sessionId, exerciseIds) {
  const [rows] = await conn.query(
    `SELECT exercise_id, reps, COUNT(*) AS n
       FROM set_logs
      WHERE session_id = ? AND exercise_id IN (?)
      GROUP BY exercise_id, reps`,
    [sessionId, exerciseIds],
  );

  const byExercise = new Map();
  for (const id of exerciseIds) byExercise.set(id, { sets: 0, best: null, bestN: 0 });

  for (const row of rows) {
    const entry = byExercise.get(row.exercise_id);
    entry.sets += Number(row.n);
    if (row.reps === null) continue;
    const n = Number(row.n);
    // Strictly greater, or equal with a higher rep count: ties go up.
    if (n > entry.bestN || (n === entry.bestN && row.reps > entry.best)) {
      entry.best = row.reps;
      entry.bestN = n;
    }
  }

  return byExercise;
}

/// How many days a week this user trains, from the days they chose.
///
/// A profile fact, not a plan one -- user_training_days survives every
/// regenerate, which is exactly why it is the right source here.
async function trainingDayCount(conn, userId) {
  const [[{ chosen }]] = await conn.query(
    'SELECT COUNT(*) AS chosen FROM user_training_days WHERE user_id = ?', [userId],
  );
  return Number(chosen);
}

/// Turns a completed session into a day of the user's own plan.
///
/// One transaction throughout: a refusal partway must not leave a plan row
/// with no exercises, which the Plan tab would render as an empty week.
async function createPlanFromSession(pool, userId, { sessionId, splitStyle, dayNo = null }) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [sessions] = await conn.query(
      `SELECT session_id, status, plan_id, plan_day_no, duration_min
         FROM workout_sessions WHERE session_id = ? AND user_id = ?`,
      [sessionId, userId],
    );
    // Scoped to the caller, so another account's session is indistinguishable
    // from one that does not exist -- which is what it should be.
    if (sessions.length === 0) {
      throw AppError.notFound('SESSION_NOT_FOUND', 'That workout does not exist.');
    }
    const session = sessions[0];
    if (session.status !== 'completed') {
      throw AppError.conflict(
        'SESSION_NOT_COMPLETED',
        'Only a finished workout can become part of your plan.',
      );
    }

    const exerciseIds = await sessionExerciseIds(conn, session);
    if (exerciseIds.length === 0) {
      throw AppError.conflict(
        'SESSION_HAS_NO_EXERCISES',
        'That workout has no exercises left in the library.',
      );
    }

    // Every decision reads the ACTIVE plan's source. A custom plan the
    // generator has already replaced is deactivated, and reviving it is out of
    // scope -- so a user in that position gets a fresh custom plan rather than
    // silently resurrecting an old one.
    const [active] = await conn.query(
      `SELECT plan_id, source FROM workout_plans
        WHERE user_id = ? AND is_active = TRUE ORDER BY plan_id DESC LIMIT 1`,
      [userId],
    );
    const extending = active.length > 0 && active[0].source === 'custom';

    let planId;
    let targetDay;

    if (extending) {
      planId = active[0].plan_id;
      const [[{ lastDay }]] = await conn.query(
        'SELECT COALESCE(MAX(day_no), 0) AS lastDay FROM plan_exercises WHERE plan_id = ?',
        [planId],
      );
      targetDay = dayNo ?? lastDay + 1;
      if (targetDay < 1 || targetDay > lastDay + 1) {
        // A gap would leave nextPlanDayNo rotating through a day that has no
        // exercises, which the logger renders as an empty workout.
        throw AppError.badRequest(
          'INVALID_DAY_NO',
          `dayNo must be between 1 and ${lastDay + 1}.`,
          [{ field: 'dayNo', value: String(dayNo) }],
        );
      }
      // Replacing a day means replacing it, not merging into it.
      await conn.query(
        'DELETE FROM plan_exercises WHERE plan_id = ? AND day_no = ?',
        [planId, targetDay],
      );
    } else {
      await conn.query(
        'UPDATE workout_plans SET is_active = FALSE WHERE user_id = ?', [userId],
      );
      const [plan] = await conn.query(
        `INSERT INTO workout_plans
           (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active, source)
         VALUES (?, ?, ?, ?, ?, 1, TRUE, 'custom')`,
        [
          userId,
          `My ${SPLIT_LABELS[splitStyle] ?? splitStyle}`,
          splitStyle,
          1,
          session.duration_min ?? 45,
        ],
      );
      planId = plan.insertId;
      targetDay = 1;
    }

    const prescription = await prescriptionFromLogs(conn, sessionId, exerciseIds);

    for (const [index, exerciseId] of exerciseIds.entries()) {
      const logged = prescription.get(exerciseId);
      await conn.query(
        `INSERT INTO plan_exercises
           (plan_id, exercise_id, day_no, order_no, target_sets, target_reps)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          planId,
          exerciseId,
          targetDay,
          index + 1,
          logged.sets > 0 ? logged.sets : 3,
          logged.best === null ? '8-12' : String(logged.best),
        ],
      );
    }

    // Recomputed on every write rather than only at creation: both are
    // derivations from facts that change as the plan grows.
    const [[{ dayCount }]] = await conn.query(
      'SELECT COUNT(DISTINCT day_no) AS dayCount FROM plan_exercises WHERE plan_id = ?',
      [planId],
    );
    const chosenDays = await trainingDayCount(conn, userId);
    const [[{ meanMinutes }]] = await conn.query(
      `SELECT AVG(duration_min) AS meanMinutes
         FROM workout_sessions
        WHERE user_id = ? AND status = 'completed' AND duration_min IS NOT NULL`,
      [userId],
    );
    const length = meanMinutes === null
      ? 45
      : Math.min(MAX_SESSION_MIN, Math.max(MIN_SESSION_MIN, Math.round(Number(meanMinutes))));

    await conn.query(
      'UPDATE workout_plans SET days_per_week = ?, session_length_min = ? WHERE plan_id = ?',
      [chosenDays > 0 ? chosenDays : Number(dayCount), length, planId],
    );

    await conn.commit();
    return { planId };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  resolveExerciseIds, savePlan, getActivePlan, dayNamesFor, createPlanFromSession,
};
