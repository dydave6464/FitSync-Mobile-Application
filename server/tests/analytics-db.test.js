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

  await t.test('a session dated exactly the window length ago is excluded, not shifted into an extra bucket', async () => {
    // week: days = 7. A session at daysAgo 7 sits exactly on the boundary --
    // it must not appear anywhere in the output, not even mis-filed.
    const userId = await makeUser('boundary-week-out@example.com');
    await writeSession(userId, { daysAgo: 7, volume: 900 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.ok(buckets.every((b) => b.volumeKg === 0), 'day 7 is outside a 7-day window');
  });

  await t.test('a session one day inside the week window still lands in the first bucket', async () => {
    // Proves the boundary moved by exactly one day, not more: day 6 must
    // still be visible, and in the oldest (first) slot.
    const userId = await makeUser('boundary-week-in@example.com');
    await writeSession(userId, { daysAgo: 6, volume: 900 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.equal(buckets[0].volumeKg, 900, 'day 6 is the oldest day still inside the window');
  });

  await t.test('a day-7 session never joins day 6 in the first bucket, even under the clamp', async () => {
    // Regression guard for the >= boundary bug: with a bare `>`, day 7 never
    // enters the query at all, so it cannot land anywhere -- including
    // folded into bucket 0 by the LEAST() clamp. If the boundary ever
    // reverts to `>=`, the clamp keeps day 7's volume visible rather than
    // vanishing it, but folded into bucket 0 alongside day 6 -- which this
    // assertion catches, unlike a bare "all buckets zero" check.
    const userId = await makeUser('boundary-week-noclamp@example.com');
    await writeSession(userId, { daysAgo: 6, volume: 900 });
    await writeSession(userId, { daysAgo: 7, volume: 400 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'week');
    assert.equal(buckets[0].volumeKg, 900, 'day 7 must not be folded into the day-6 bucket');
  });

  await t.test('a session dated exactly the month window length ago is excluded from buckets', async () => {
    // month: days = 30. Mirrors the week boundary case above -- month and
    // year previously had only a length assertion, never a data one.
    const userId = await makeUser('boundary-month-out@example.com');
    await writeSession(userId, { daysAgo: 30, volume: 900 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'month');
    assert.ok(buckets.every((b) => b.volumeKg === 0), 'day 30 is outside a 30-day window');
  });

  await t.test('a session one day inside the month window still lands in the first bucket', async () => {
    const userId = await makeUser('boundary-month-in@example.com');
    await writeSession(userId, { daysAgo: 29, volume: 900 });
    const buckets = await analytics.readVolumeBuckets(pool, userId, 'month');
    assert.equal(buckets[0].volumeKg, 900, 'day 29 is the oldest day still inside a 30-day window');
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

  await t.test('a session dated exactly the window length ago contributes no sets', async () => {
    // Mirrors the readVolumeBuckets/readVolumeChange boundary fix: a session
    // at daysAgo 7 must not appear in the week's muscle rows, while one at
    // daysAgo 6 must. Unlike the bucket case, a dropped set here shows up
    // directly in the COUNT, so this one CAN go genuinely red.
    const userId = await makeUser('muscle-boundary@example.com');
    await writeSession(userId, { daysAgo: 7, sets: 5, exerciseId: exRows[0].exercise_id });
    await writeSession(userId, { daysAgo: 6, sets: 3, exerciseId: exRows[0].exercise_id });

    const rows = await analytics.readSetsByMuscle(pool, userId, 'week');
    const total = rows.reduce((sum, r) => sum + r.sets, 0);
    assert.equal(total, 3, 'day 7 is outside the window; only day 6 counts');
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

  await t.test('a session exactly one window old counts as previous, not current', async () => {
    // week: days = 7. A session at daysAgo 7 sits on the boundary between
    // the two windows -- it belongs to the PREVIOUS week, not this one.
    const userId = await makeUser('boundary-change@example.com');
    await writeSession(userId, { daysAgo: 7, volume: 900 });
    const change = await analytics.readVolumeChange(pool, userId, 'week');
    assert.equal(change.totalKg, 0, 'day 7 must not count as current');
    assert.equal(change.previousKg, 900, 'day 7 counts as previous');
  });

  await t.test('an unknown period is null', async () => {
    const userId = await makeUser('badperiod@example.com');
    assert.equal(await analytics.readVolumeBuckets(pool, userId, 'decade'), null);
    assert.equal(await analytics.readVolumeChange(pool, userId, 'decade'), null);
  });
});
