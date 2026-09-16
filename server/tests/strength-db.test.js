'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const strength = require('../src/db/strength');

test('strength db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [[ex]] = await pool.query("SELECT exercise_id FROM exercises WHERE status='live' LIMIT 1");
  const exerciseId = ex.exercise_id;

  const makeUser = async (email) => {
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'S')`,
      [email],
    );
    return res.insertId;
  };

  const writeSets = async (userId, daysAgo, sets) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
      [userId, daysAgo],
    );
    let n = 0;
    for (const [weight, reps] of sets) {
      n += 1;
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, ?, ?, TRUE)`,
        [s.insertId, exerciseId, n, weight, reps],
      );
    }
  };

  await t.test('epley is weight times one plus reps over thirty', () => {
    assert.equal(strength.epley(100, 0), 100);
    assert.equal(strength.epley(60, 10), 80);
  });

  await t.test('one session plots per set, not a lone dot', async () => {
    const userId = await makeUser('day-one@example.com');
    await writeSets(userId, 0, [[60, 10], [60, 9], [57.5, 8]]);

    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.equal(series.xAxis, 'set', 'the axis becomes set number');
    assert.equal(series.points.length, 3, 'a real three-point line on day one');
    assert.equal(series.points[0].label, '1');
    assert.equal(series.points[0].e1rmKg, 80);
  });

  await t.test('two sessions plot one best point each, by date', async () => {
    const userId = await makeUser('two@example.com');
    await writeSets(userId, 3, [[60, 10], [60, 5]]);
    await writeSets(userId, 0, [[65, 8], [65, 10]]);

    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.equal(series.xAxis, 'date');
    assert.equal(series.points.length, 2, 'one per session');
    assert.equal(series.points[0].e1rmKg, 80, 'the session best, not its last set');
    assert.ok(series.points[1].e1rmKg > series.points[0].e1rmKg);
  });

  await t.test('a set above twelve reps is excluded, not clamped', async () => {
    const userId = await makeUser('highrep@example.com');
    await writeSets(userId, 0, [[40, 20]]);

    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.equal(series.points.length, 0, 'Epley does not survive 20 reps');
  });

  await t.test('a bodyweight set is excluded', async () => {
    const userId = await makeUser('bw@example.com');
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', CURDATE())`, [userId],
    );
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
       VALUES (?, ?, 1, NULL, 12, TRUE)`,
      [s.insertId, exerciseId],
    );

    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.equal(series.points.length, 0, 'no one-rep max without a load');
  });

  await t.test('an uncompleted set is excluded', async () => {
    const userId = await makeUser('incomplete@example.com');
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', CURDATE())`, [userId],
    );
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
       VALUES (?, ?, 1, 80, 5, FALSE)`,
      [s.insertId, exerciseId],
    );
    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.equal(series.points.length, 0);
  });

  await t.test('options are ordered by how much data they have', async () => {
    const userId = await makeUser('options@example.com');
    await writeSets(userId, 0, [[60, 10], [60, 10], [60, 10]]);

    const options = await strength.readOptions(pool, userId, 'week');
    assert.ok(options.length >= 1);
    assert.equal(options[0].exerciseId, exerciseId);
    assert.equal(options[0].sets, 3);
    assert.ok(typeof options[0].name === 'string');
  });

  await t.test('no logged sets is an empty series, not an invented one', async () => {
    const userId = await makeUser('none@example.com');
    const series = await strength.readSeries(pool, userId, exerciseId, 'week');
    assert.deepEqual(series.points, []);
    assert.deepEqual(await strength.readOptions(pool, userId, 'week'), []);
  });
});
