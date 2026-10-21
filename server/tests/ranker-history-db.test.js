'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const { readRankerHistory } = require('../src/db/ranker-history');

test('ranker history', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const exerciseFor = async (muscle) => {
    const [[row]] = await pool.query(
      'SELECT exercise_id FROM exercises WHERE muscle_group = ? LIMIT 1', [muscle]);
    return row.exercise_id;
  };
  const abs = await exerciseFor('abs');
  const biceps = await exerciseFor('biceps');
  const quads = await exerciseFor('quads');

  let seq = 0;
  const makeUser = async () => {
    seq += 1;
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'H')`,
      [`history${seq}@example.com`]);
    return res.insertId;
  };

  /// A plan whose day 1 prescribes [exerciseIds].
  const makePlan = async (userId, exerciseIds) => {
    const [p] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
       VALUES (?, 'P', 'full_body', 3, 45, 1, 1)`, [userId]);
    let n = 0;
    for (const id of exerciseIds) {
      n += 1;
      await pool.query(
        `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps, day_no)
         VALUES (?, ?, ?, 3, '8-12', 1)`, [p.insertId, id, n]);
    }
    return p.insertId;
  };

  /// A completed workout [daysAgo] from [planId] (or none) with one completed
  /// set of each of [doneIds].
  const workout = async (userId, daysAgo, doneIds, planId = null, status = 'completed') => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, plan_id, plan_day_no)
       VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY), ?, ?)`,
      [userId, status, daysAgo, planId, planId ? 1 : null]);
    let n = 0;
    for (const id of doneIds) {
      n += 1;
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, 20, 10, TRUE)`, [s.insertId, id, n]);
    }
  };

  const swap = async (userId, daysAgo, rejected, chosen, planId) => {
    await pool.query(
      `INSERT INTO plan_swaps (user_id, plan_id, rejected_exercise_id, chosen_exercise_id, muscle_group, swapped_at)
       VALUES (?, ?, ?, ?, 'x', DATE_SUB(NOW(), INTERVAL ? DAY))`,
      [userId, planId, rejected, chosen, daysAgo]);
  };

  await t.test('a new user has no history', async () => {
    assert.deepEqual(await readRankerHistory(pool, await makeUser()),
      { muscleDaysAgo: {}, exercises: {} });
  });

  await t.test('done, skipped and days since, from completed workouts', async () => {
    const u = await makeUser();
    const plan = await makePlan(u, [abs, biceps]);
    await workout(u, 3, [abs], plan);          // biceps prescribed, skipped
    await workout(u, 1, [abs, biceps], plan);  // both done
    const h = await readRankerHistory(pool, u);
    assert.deepEqual(h.exercises[String(abs)], { done: 2, skipped: 0, swapped: 0 });
    assert.deepEqual(h.exercises[String(biceps)], { done: 1, skipped: 1, swapped: 0 });
    assert.equal(h.muscleDaysAgo.abs, 1);
    assert.equal(h.muscleDaysAgo.biceps, 1);
  });

  await t.test('an unfinished workout counts for nothing', async () => {
    const u = await makeUser();
    const plan = await makePlan(u, [abs]);
    await workout(u, 1, [abs], plan, 'in_progress');
    assert.deepEqual(await readRankerHistory(pool, u), { muscleDaysAgo: {}, exercises: {} });
  });

  await t.test('swaps count against the exercise swapped out', async () => {
    const u = await makeUser();
    const plan = await makePlan(u, [quads]);
    await swap(u, 2, quads, abs, plan);
    await swap(u, 5, quads, abs, plan);
    assert.equal((await readRankerHistory(pool, u)).exercises[String(quads)].swapped, 2);
  });

  await t.test('only the last 90 days count, and counts are capped at 5', async () => {
    const u = await makeUser();
    const plan = await makePlan(u, [abs]);
    for (let d = 1; d <= 7; d += 1) await workout(u, d, [abs], plan);
    await workout(u, 120, [abs], plan);
    const h = await readRankerHistory(pool, u);
    assert.equal(h.exercises[String(abs)].done, 5);
  });

  await t.test('days since trained is capped at 14', async () => {
    const u = await makeUser();
    await workout(u, 30, [quads]);
    assert.equal((await readRankerHistory(pool, u)).muscleDaysAgo.quads, 14);
  });

  await t.test('before= sees only earlier days, measured from that day', async () => {
    const u = await makeUser();
    const plan = await makePlan(u, [abs]);
    await workout(u, 10, [abs], plan);
    await workout(u, 2, [abs], plan);
    const [[{ d }]] = await pool.query(
      "SELECT DATE_FORMAT(CURDATE() - INTERVAL 2 DAY, '%Y-%m-%d') AS d");
    const h = await readRankerHistory(pool, u, { before: d });
    assert.equal(h.exercises[String(abs)].done, 1);
    assert.equal(h.muscleDaysAgo.abs, 8);
  });
});
