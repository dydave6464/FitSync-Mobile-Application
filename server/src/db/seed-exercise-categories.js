'use strict';
const { createPool } = require('./pool');
const { reconcile } = require('./reconcile');
const { classifyCategory } = require('./classify-categories');

// Reads every live exercise, computes its category, and reconciles
// exercise_categories to match. Rows with is_manual = 1 are a human's
// judgement and are never written or deleted here. See the design, section 5.

const LIVE_EXERCISES = `
  SELECT exercise_id, name FROM exercises WHERE status = 'live'
`;

async function seedExerciseCategories(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    const [exercises] = await pool.query(LIVE_EXERCISES);

    // exercise_id is the PRIMARY KEY here, unlike the composite-keyed safety
    // tables. A manual row whose category differs from the computed one has a
    // different composite key, so blocking on (exercise_id, category) would
    // let the INSERT through and collide. Block on exercise_id alone.
    const [manualRows] = await pool.query(
      'SELECT exercise_id FROM exercise_categories WHERE is_manual = 1',
    );
    const blocked = new Set(manualRows.map((r) => r.exercise_id));

    const counts = { strength: 0, stretch: 0, mobility: 0, other: 0 };
    const wanted = [];
    for (const exercise of exercises) {
      const category = classifyCategory(exercise);
      counts[category] += 1;
      if (blocked.has(exercise.exercise_id)) continue;
      wanted.push({ exercise_id: exercise.exercise_id, category });
    }

    const [existing] = await pool.query(
      'SELECT exercise_id, category FROM exercise_categories WHERE is_manual = 0',
    );

    const result = await reconcile(
      pool, 'exercise_categories', ['exercise_id', 'category'], wanted, existing,
    );
    return { ...result, manual: blocked.size, counts };
  } finally {
    await pool.end();
  }
}

module.exports = { seedExerciseCategories };
