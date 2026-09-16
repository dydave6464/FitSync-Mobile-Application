'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const analytics = require('../src/db/analytics');

test('analytics db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [exRows] = await pool.query(
    "SELECT exercise_id, muscle_group FROM exercises WHERE status='live' LIMIT 2",
  );

  const makeUser = async (email) => {
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'A')`,
      [email],
    );
    return res.insertId;
  };

  const writeSession = async (userId, { daysAgo, volume = 1000, sets = 0, exerciseId }) => {
    const [res] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, total_volume_kg)
       VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY), ?)`,
      [userId, daysAgo, volume],
    );
    for (let i = 1; i <= sets; i += 1) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, 60, 10, TRUE)`,
        [res.insertId, exerciseId, i],
      );
    }
    return res.insertId;
  };

  await t.test('an empty week is seven zero buckets, not an empty array', async () => {
    const userId = await makeUser('empty@example.com');
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.equal(buckets.length, 7, 'always a full line');
    assert.ok(buckets.every((b) => b.volumeKg === 0));
  });

  await t.test('volume lands in the right bucket, oldest first', async () => {
    const userId = await makeUser('buckets@example.com');
    await writeSession(userId, { daysAgo: 0, volume: 500 });
    await writeSession(userId, { daysAgo: 6, volume: 900 });

    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.equal(buckets[0].volumeKg, 900, 'six days ago is first');
    assert.equal(buckets[6].volumeKg, 500, 'today is last');
  });

  await t.test('a session outside the window is excluded', async () => {
    const userId = await makeUser('outside@example.com');
    await writeSession(userId, { daysAgo: 40, volume: 900 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.ok(buckets.every((b) => b.volumeKg === 0));
  });

  await t.test('month is six buckets and year is twelve', async () => {
    const userId = await makeUser('shape@example.com');
    assert.equal((await analytics.readVolumeBuckets(pool, userId, 'month')).length, 6);
    assert.equal((await analytics.readVolumeBuckets(pool, userId, 'year')).length, 12);
  });

  await t.test('adherence without a plan has no target', async () => {
    const userId = await makeUser('noplan@example.com');
    await writeSession(userId, { daysAgo: 1 });

    const a = await analytics.readAdherence(pool, userId, 'week');
    assert.equal(a.done, 1);
    assert.equal(a.target, null, 'the plan is what defines a target');
  });

  await t.test('adherence multiplies days_per_week by whole weeks', async () => {
    const userId = await makeUser('plan@example.com');
    await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, 'P', 'full_body', 4, 45, TRUE)`,
      [userId],
    );
    assert.equal((await analytics.readAdherence(pool, userId, 'week')).target, 4);
    assert.equal((await analytics.readAdherence(pool, userId, 'month')).target, 16);
    assert.equal((await analytics.readAdherence(pool, userId, 'year')).target, 208);
  });

  await t.test('the count cannot exceed its own target window', async () => {
    // Sessions on days 28 and 29 fall inside a 30-day window but outside the
    // 4-week target the month denominator describes. Counting them would let
    // a diligent user score 17/16, and a ratio over 100% reads as a bug.
    const userId = await makeUser('window@example.com');
    await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, 'P', 'full_body', 1, 45, TRUE)`,
      [userId],
    );
    await writeSession(userId, { daysAgo: 29 });

    const a = await analytics.readAdherence(pool, userId, 'month');
    assert.equal(a.done, 0, 'day 29 is outside the 28-day target window');
  });

  await t.test('sets group by muscle, descending', async () => {
    const userId = await makeUser('muscle@example.com');
    await writeSession(userId, { daysAgo: 1, sets: 5, exerciseId: exRows[0].exercise_id });
    await writeSession(userId, { daysAgo: 2, sets: 2, exerciseId: exRows[1].exercise_id });

    const rows = await analytics.readSetsByMuscle(pool, userId, 'week');
    assert.ok(rows.length >= 1);
    assert.equal(rows[0].sets, exRows[0].muscle_group === exRows[1].muscle_group ? 7 : 5);
    for (let i = 1; i < rows.length; i += 1) {
      assert.ok(rows[i - 1].sets >= rows[i].sets, 'descending');
    }
  });

  await t.test('the trend compares this window with the one before it', async () => {
    const userId = await makeUser('trend@example.com');
    await writeSession(userId, { daysAgo: 1, volume: 1100 });   // this week
    await writeSession(userId, { daysAgo: 9, volume: 1000 });   // the week before

    const change = await analytics.readVolumeChange(pool, userId, 'week');
    assert.equal(change.totalKg, 1100);
    assert.equal(change.previousKg, 1000);
    assert.equal(change.changePct, 10);
  });

  await t.test('no previous volume means no percentage to show', async () => {
    // A first week has nothing to be up or down against, and "+100%" against
    // zero is not a fact about training.
    const userId = await makeUser('firstweek@example.com');
    await writeSession(userId, { daysAgo: 1, volume: 1100 });

    const change = await analytics.readVolumeChange(pool, userId, 'week');
    assert.equal(change.previousKg, 0);
    assert.equal(change.changePct, null);
  });

  await t.test('an unknown period is null', async () => {
    const userId = await makeUser('badperiod@example.com');
    assert.equal(await analytics.readVolumeBuckets(pool, userId, 'decade'), null);
    assert.equal(await analytics.readVolumeChange(pool, userId, 'decade'), null);
  });
});
