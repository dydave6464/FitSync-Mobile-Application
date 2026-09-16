'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const bw = require('../src/db/body-weight');

async function makeUser(pool, email = 'w@example.com') {
  const [res] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'W')`,
    [email],
  );
  return res.insertId;
}

const daysAgo = (n) => `DATE_SUB(CURDATE(), INTERVAL ${n} DAY)`;

test('body weight db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('two writes on one day produce one row', async () => {
    const userId = await makeUser(pool, 'one-a-day@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });
    await bw.writeEntry(pool, userId, { weightKg: 70.9 });

    const [rows] = await pool.query(
      'SELECT weight_kg FROM body_weight_logs WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 1);
    assert.equal(Number(rows[0].weight_kg), 70.9, 'the later write wins');
  });

  await t.test('the newest entry syncs to users.weight_kg', async () => {
    const userId = await makeUser(pool, 'sync@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });

    const [[user]] = await pool.query(
      'SELECT weight_kg FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(Number(user.weight_kg), 71.4);
  });

  await t.test('a backdated entry does not clobber the current weight', async () => {
    const userId = await makeUser(pool, 'backdate@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 70.0 });

    const [[past]] = await pool.query(`SELECT ${daysAgo(30)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 99.0, loggedOn: past.d });

    const [[user]] = await pool.query(
      'SELECT weight_kg FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(Number(user.weight_kg), 70.0, 'today still wins');
  });

  await t.test('out-of-range input is rejected', async () => {
    const userId = await makeUser(pool, 'range@example.com');
    await assert.rejects(
      () => bw.writeEntry(pool, userId, { weightKg: 4 }),
      (err) => err.code === 'WEIGHT_OUT_OF_RANGE',
    );
  });

  await t.test('a thin window widens rather than returning one point', async () => {
    const userId = await makeUser(pool, 'widen@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(40)} AS d`);
    const [[b]] = await pool.query(`SELECT ${daysAgo(35)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: b.d });

    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.widened, true);
    assert.equal(week.points.length, 2, 'both entries come back anyway');
    assert.ok(week.points[0].loggedOn < week.points[1].loggedOn, 'oldest first');
  });

  await t.test('a full window does not widen', async () => {
    const userId = await makeUser(pool, 'nowiden@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(2)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 79 });

    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.widened, false);
    assert.equal(week.points.length, 2);
  });

  await t.test('one entry overall stays one point', async () => {
    const userId = await makeUser(pool, 'single@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80 });
    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.points.length, 1, 'widening cannot invent a second');
  });

  await t.test('the reference is the goal when there is one', async () => {
    const userId = await makeUser(pool, 'goal@example.com');
    await pool.query('UPDATE users SET goal_weight_kg = 68 WHERE user_id = ?', [userId]);
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });

    assert.deepEqual(await bw.readReference(pool, userId), {
      kind: 'goal', weightKg: 68,
    });
  });

  await t.test('and the earliest entry when there is not', async () => {
    const userId = await makeUser(pool, 'start@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(10)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 75, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 73 });

    assert.deepEqual(await bw.readReference(pool, userId), {
      kind: 'start', weightKg: 75,
    });
  });

  await t.test('an unknown period is null, not an empty series', async () => {
    const userId = await makeUser(pool, 'period@example.com');
    assert.equal(await bw.readSeries(pool, userId, 'decade'), null);
  });
});
