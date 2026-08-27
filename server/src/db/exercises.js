'use strict';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

// Every query is scoped to live rows. Pending exercises are an admin review
// queue, not catalogue content.
const LIVE = "x.status = 'live'";

function buildWhere({ muscleGroup, equipment }) {
  const clauses = [LIVE];
  const params = [];
  if (muscleGroup) {
    clauses.push('x.muscle_group = ?');
    params.push(muscleGroup);
  }
  if (equipment) {
    clauses.push('e.name = ?');
    params.push(equipment);
  }
  return { sql: clauses.join(' AND '), params };
}

async function listExercises(pool, options = {}) {
  const { page = 1, limit = DEFAULT_LIMIT } = options;
  const { sql: where, params } = buildWhere(options);
  const offset = (page - 1) * limit;

  const [[{ total }]] = await pool.query(
    `SELECT COUNT(*) AS total
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE ${where}`,
    params,
  );

  // Ordering by name alone is not stable — the dataset has 6 duplicate names.
  // exercise_id breaks the tie so pages cannot overlap or skip rows.
  const [rows] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, e.name AS equipment, x.thumbnail_url
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE ${where}
      ORDER BY x.name ASC, x.exercise_id ASC
      LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );

  return { rows, total };
}

async function getExerciseById(pool, exerciseId) {
  const [rows] = await pool.query(
    `SELECT x.exercise_id, x.name, x.muscle_group, e.name AS equipment,
            x.thumbnail_url, x.animation_url
       FROM exercises x
       LEFT JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE x.exercise_id = ? AND ${LIVE}`,
    [exerciseId],
  );
  if (rows.length === 0) return null;

  const [cues] = await pool.query(
    'SELECT cue_text FROM coaching_cues WHERE exercise_id = ? ORDER BY order_no ASC',
    [exerciseId],
  );

  return { ...rows[0], cues: cues.map((c) => c.cue_text) };
}

async function listFilters(pool) {
  const [muscleGroups] = await pool.query(
    `SELECT x.muscle_group AS value, COUNT(*) AS count
       FROM exercises x
      WHERE ${LIVE}
      GROUP BY x.muscle_group
      ORDER BY x.muscle_group ASC`,
  );

  const [equipment] = await pool.query(
    `SELECT e.name AS value, COUNT(*) AS count
       FROM exercises x
       JOIN equipment e ON e.equipment_id = x.equipment_id
      WHERE ${LIVE}
      GROUP BY e.name
      ORDER BY e.name ASC`,
  );

  return { muscleGroups, equipment };
}

module.exports = {
  DEFAULT_LIMIT,
  MAX_LIMIT,
  listExercises,
  getExerciseById,
  listFilters,
};
