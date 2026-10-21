'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const {
  CSV_COLUMNS, exportRankerRows, countAccounts, toCsv,
} = require('../src/db/ranker-export');

test('ranker export', async (t) => {
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

  const [u] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name, main_goal, fitness_level, training_location)
     VALUES ('export@example.com', 'x', 'E', 'build_muscle', 'intermediate', 'home_gym')`);
  const userId = u.insertId;
  const [p] = await pool.query(
    `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
     VALUES (?, 'P', 'upper_lower', 3, 60, 1, 1)`, [userId]);
  for (const [n, id] of [[1, abs], [2, biceps]]) {
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps, day_no)
       VALUES (?, ?, ?, 3, '8-12', 1)`, [p.insertId, id, n]);
  }
  const workout = async (daysAgo, doneIds) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, plan_id, plan_day_no)
       VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY), ?, 1)`,
      [userId, daysAgo, p.insertId]);
    let n = 0;
    for (const id of doneIds) {
      n += 1;
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, 20, 10, TRUE)`, [s.insertId, id, n]);
    }
  };
  await workout(6, [abs, biceps]);
  await workout(2, [abs]);                   // biceps skipped
  await pool.query(
    `INSERT INTO plan_swaps (user_id, plan_id, rejected_exercise_id, chosen_exercise_id, muscle_group, swapped_at)
     VALUES (?, ?, ?, ?, 'biceps', DATE_SUB(NOW(), INTERVAL 1 DAY))`,
    [userId, p.insertId, biceps, abs]);

  await pool.query(
    `INSERT INTO exercise_preferences (exercise_id, priority, beginner_friendly)
     VALUES (?, 'first', TRUE), (?, 'never', FALSE)`, [biceps, abs]);

  // A second user whose slot was swapped AFTER their workout: plan_exercises
  // now names the replacement, but the workout prescribed the original.
  const [[{ exercise_id: otherAbs }]] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE muscle_group = 'abs' AND exercise_id <> ? LIMIT 1", [abs]);
  const quads = await exerciseFor('quads');
  const [u2] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name) VALUES ('swap@example.com', 'x', 'S')`);
  const [p2] = await pool.query(
    `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
     VALUES (?, 'P2', 'push_pull_legs', 3, 45, 1, 1)`, [u2.insertId]);
  const [slot] = await pool.query(
    `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps, day_no)
     VALUES (?, ?, 1, 3, '8-12', 1)`, [p2.insertId, otherAbs]);
  const [s2] = await pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date, plan_id, plan_day_no)
     VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL 3 DAY), ?, 1)`, [u2.insertId, p2.insertId]);
  await pool.query(
    `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
     VALUES (?, ?, 1, 20, 10, TRUE)`, [s2.insertId, quads]);
  await pool.query(
    `INSERT INTO plan_swaps (user_id, plan_id, plan_exercise_id, rejected_exercise_id, chosen_exercise_id, muscle_group, swapped_at)
     VALUES (?, ?, ?, ?, ?, 'quads', DATE_SUB(NOW(), INTERVAL 1 DAY))`,
    [u2.insertId, p2.insertId, slot.insertId, quads, otherAbs]);

  // A demo account (as scripts/seed-demo.js creates): a completed plan
  // workout and a swap, both of which must stay out when it is excluded.
  const [u3] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name) VALUES ('demo@example.com', 'x', 'D')`);
  const [p3] = await pool.query(
    `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, week_no, is_active)
     VALUES (?, 'P3', 'full_body', 3, 45, 1, 1)`, [u3.insertId]);
  await pool.query(
    `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps, day_no)
     VALUES (?, ?, 1, 3, '8-12', 1)`, [p3.insertId, biceps]);
  await pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date, plan_id, plan_day_no)
     VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL 5 DAY), ?, 1)`, [u3.insertId, p3.insertId]);
  await pool.query(
    `INSERT INTO plan_swaps (user_id, plan_id, rejected_exercise_id, chosen_exercise_id, muscle_group, swapped_at)
     VALUES (?, ?, ?, ?, 'biceps', DATE_SUB(NOW(), INTERVAL 1 DAY))`,
    [u3.insertId, p3.insertId, biceps, abs]);

  const everyone = await exportRankerRows(pool);
  const excluded = ['demo@example.com', 'absent@example.com'];
  const rows = await exportRankerRows(pool, { excludeEmails: excluded });
  const mine = rows.filter((r) => r.user_id === userId);

  await t.test('excluded accounts are left out of both workouts and swaps', async () => {
    const demo = (list) => list.filter((r) => r.user_id === u3.insertId).map((r) => r.kind);
    assert.deepEqual(demo(everyone).sort(), ['prescribed', 'swap']);
    assert.deepEqual(demo(rows), []);
    assert.equal(rows.length, everyone.length - 2);
    assert.equal(await countAccounts(pool, excluded), 1);
    assert.equal(await countAccounts(pool, []), 0);
  });

  await t.test('one row per prescribed exercise per workout, plus one per swap', async () => {
    assert.equal(mine.filter((r) => r.kind === 'prescribed').length, 4);
    assert.equal(mine.filter((r) => r.kind === 'swap').length, 1);
  });

  await t.test('labels: logged = 1, skipped = 0, swapped out = 0', async () => {
    const bicepsRows = rows.filter((r) => r.exercise_id === biceps)
      .sort((a, b) => a.event_date.localeCompare(b.event_date));
    assert.deepEqual(bicepsRows.map((r) => [r.kind, r.done]),
      [['prescribed', 1], ['prescribed', 0], ['swap', 0]]);
  });

  await t.test('history is as it was then: nothing from that day or later', async () => {
    const [first, second] = rows
      .filter((r) => r.kind === 'prescribed' && r.exercise_id === abs)
      .sort((a, b) => a.event_date.localeCompare(b.event_date));
    assert.equal(first.times_done, 0);
    assert.equal(first.days_since_trained, '');
    assert.equal(second.times_done, 1);
    assert.equal(second.days_since_trained, 4);
    const swapRow = mine.find((r) => r.kind === 'swap');
    assert.equal(swapRow.times_skipped, 1);
  });

  await t.test('profile, plan and catalogue columns', async () => {
    const r = rows[0];
    assert.equal(r.user_id, userId);
    assert.equal(r.main_goal, 'build_muscle');
    assert.equal(r.fitness_level, 'intermediate');
    assert.equal(r.training_location, 'home_gym');
    assert.equal(r.split_style, 'upper_lower');
    assert.equal(r.session_length_min, 60);
    assert.ok(['first', 'alternative', 'unmarked'].includes(r.mark));
    assert.ok([0, 1].includes(r.beginner_friendly));
    assert.ok([0, 1].includes(r.picked_equipment));
    assert.ok(typeof r.equipment_name === 'string' && r.equipment_name.length > 0);
  });

  await t.test('a slot swapped after the workout exports what the workout prescribed', async () => {
    const theirs = rows.filter((r) => r.user_id === u2.insertId && r.kind === 'prescribed');
    assert.deepEqual(theirs.map((r) => [r.exercise_id, r.done]), [[quads, 1]]);
  });

  await t.test('marks: curated first kept, search_only/never read as unmarked', async () => {
    for (const r of rows.filter((x) => x.exercise_id === biceps)) {
      assert.equal(r.mark, 'first');
      assert.equal(r.beginner_friendly, 1);
    }
    for (const r of rows.filter((x) => x.exercise_id === abs)) {
      assert.equal(r.mark, 'unmarked');
      assert.equal(r.beginner_friendly, 0);
    }
  });

  await t.test('the CSV header is the agreed contract, and fields are escaped', async () => {
    assert.deepEqual(CSV_COLUMNS, [
      'user_id', 'event_date', 'kind', 'main_goal', 'fitness_level',
      'training_location', 'session_length_min', 'split_style', 'health_caution',
      'exercise_id', 'mark', 'beginner_friendly', 'equipment_name',
      'picked_equipment', 'muscle_group', 'days_since_trained', 'times_done',
      'times_skipped', 'times_swapped', 'done',
    ]);
    const csv = toCsv([{ ...rows[0], equipment_name: 'a "b", c' }]);
    const [header, line] = csv.trimEnd().split('\n');
    assert.equal(header, CSV_COLUMNS.join(','));
    assert.match(line, /"a ""b"", c"/);
  });
});
