'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { readTrainingLoad } = require('../src/db/training-load');

/// Inserts a finished session `daysAgo` days back carrying `volumeKg`.
async function logSession(pool, userId, daysAgo, volumeKg) {
  await pool.query(
    `INSERT INTO workout_sessions (user_id, session_date, status, total_volume_kg)
     VALUES (?, DATE_SUB(CURDATE(), INTERVAL ? DAY), 'completed', ?)`,
    [userId, daysAgo, volumeKg],
  );
}

async function freshUser(pool, email) {
  const [res] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name)
     VALUES (?, 'x', 'Test User')`,
    [email],
  );
  return res.insertId;
}

test('training load index', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('an account with no history scores zero', async () => {
    const userId = await freshUser(pool, 'load-none@example.com');
    assert.equal(await readTrainingLoad(pool, userId), 0);
  });

  await t.test('training at the usual rate scores about 100', async () => {
    const userId = await freshUser(pool, 'load-steady@example.com');
    // 1000kg in each of the last four weeks, including this one.
    for (const daysAgo of [1, 8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    const load = await readTrainingLoad(pool, userId);
    assert.ok(Math.abs(load - 100) < 1, `expected ~100, got ${load}`);
  });

  await t.test('a spike is clamped at 140', async () => {
    const userId = await freshUser(pool, 'load-spike@example.com');
    await logSession(pool, userId, 22, 100);   // a quiet baseline week
    await logSession(pool, userId, 1, 100000); // then an enormous week
    assert.equal(await readTrainingLoad(pool, userId), 140);
  });
});
