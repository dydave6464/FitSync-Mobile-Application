'use strict';

/// A set that counts toward a lift goal: completed, loaded, at least one rep,
/// in a finished workout. The PR count's SET_QUALIFIES without its rep cap --
/// a goal is about the weight actually lifted, not an estimate.
const COUNTS = `s.status = 'completed'
    AND sl.is_completed = TRUE
    AND sl.weight_kg IS NOT NULL AND sl.weight_kg > 0
    AND sl.reps >= 1`;

const GOAL_SELECT = `
  SELECT g.goal_id, g.exercise_id, e.name AS exercise_name, g.target_kg, g.created_at,
         (SELECT MAX(sl.weight_kg)
            FROM set_logs sl
            JOIN workout_sessions s ON s.session_id = sl.session_id
           WHERE s.user_id = g.user_id AND sl.exercise_id = g.exercise_id
             AND ${COUNTS}) AS best_kg,
         (SELECT DATE_FORMAT(MIN(s.session_date), '%Y-%m-%d')
            FROM set_logs sl
            JOIN workout_sessions s ON s.session_id = sl.session_id
           WHERE s.user_id = g.user_id AND sl.exercise_id = g.exercise_id
             AND ${COUNTS} AND sl.weight_kg >= g.target_kg) AS reached_on
    FROM lift_goals g
    JOIN exercises e ON e.exercise_id = g.exercise_id`;

function toGoal(r) {
  return {
    goalId: r.goal_id,
    exerciseId: r.exercise_id,
    exerciseName: r.exercise_name,
    targetKg: Number(r.target_kg),
    bestKg: r.best_kg === null ? null : Number(r.best_kg),
    reachedOn: r.reached_on,
  };
}

/// [userId]'s goals: unreached first, newest first; then reached, most
/// recently reached first.
async function listGoals(pool, userId) {
  const [rows] = await pool.query(
    `SELECT * FROM (${GOAL_SELECT} WHERE g.user_id = ?) x
      ORDER BY x.reached_on IS NOT NULL, x.reached_on DESC, x.created_at DESC, x.goal_id DESC`,
    [userId],
  );
  return rows.map(toGoal);
}

/// One goal, or null when it is missing or someone else's.
async function readGoal(pool, userId, goalId) {
  const [rows] = await pool.query(
    `${GOAL_SELECT} WHERE g.user_id = ? AND g.goal_id = ?`, [userId, goalId],
  );
  return rows.length ? toGoal(rows[0]) : null;
}

async function createGoal(pool, userId, exerciseId, targetKg) {
  const [res] = await pool.query(
    'INSERT INTO lift_goals (user_id, exercise_id, target_kg) VALUES (?, ?, ?)',
    [userId, exerciseId, targetKg],
  );
  return readGoal(pool, userId, res.insertId);
}

/// False when there was no such goal of [userId]'s to delete.
async function deleteGoal(pool, userId, goalId) {
  const [res] = await pool.query(
    'DELETE FROM lift_goals WHERE goal_id = ? AND user_id = ?', [goalId, userId],
  );
  return res.affectedRows > 0;
}

/// [userId]'s heaviest counting set of [exerciseId], or null.
async function bestKg(pool, userId, exerciseId) {
  const [[r]] = await pool.query(
    `SELECT MAX(sl.weight_kg) AS best
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
      WHERE s.user_id = ? AND sl.exercise_id = ? AND ${COUNTS}`,
    [userId, exerciseId],
  );
  return r.best === null ? null : Number(r.best);
}

async function isLiveExercise(pool, exerciseId) {
  const [rows] = await pool.query(
    "SELECT 1 FROM exercises WHERE exercise_id = ? AND status = 'live'", [exerciseId],
  );
  return rows.length > 0;
}

/// The "Lifted before" list: every live exercise [userId] has a counting set
/// for, most sets first, each with its best.
async function listOptions(pool, userId) {
  const [rows] = await pool.query(
    `SELECT sl.exercise_id, e.name, MAX(sl.weight_kg) AS best_kg, COUNT(*) AS sets
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE s.user_id = ? AND e.status = 'live' AND ${COUNTS}
      GROUP BY sl.exercise_id, e.name
      ORDER BY sets DESC, e.name ASC`,
    [userId],
  );
  return rows.map((r) => ({
    exerciseId: r.exercise_id,
    name: r.name,
    bestKg: Number(r.best_kg),
    sets: Number(r.sets),
  }));
}

module.exports = {
  listGoals, readGoal, createGoal, deleteGoal, bestKg, isLiveExercise, listOptions,
};
