'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('GET /nutrition/recognitions/today', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const vision = { model: 'fake', async recognize() { return { items: [] }; } };
  const app = buildTestApp({ pool, vision });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async ({ pro }) => {
    seq += 1;
    const email = `today${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'T' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    if (pro) await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [userId]);
    const login = await request(app).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId,
      today: () => request(app).get('/api/v1/nutrition/recognitions/today').set(auth),
    };
  };
  // [n] rows of [status] for [userId], created at [when] (an SQL expression).
  const rows = (userId, n, status, when = 'NOW()') => pool.query(
    `INSERT INTO photo_recognitions (user_id, item_count, status, created_at)
     VALUES ${Array(n).fill(`(?, 0, '${status}', ${when})`).join(', ')}`,
    Array(n).fill(userId),
  );

  await t.test('signed out is 401; a free account is 403 PRO_REQUIRED', async () => {
    const out = await request(app).get('/api/v1/nutrition/recognitions/today').expect(401);
    assert.equal(out.body.error.code, 'UNAUTHENTICATED');
    const u = await freshUser({ pro: false });
    const res = await u.today().expect(403);
    assert.equal(res.body.error.code, 'PRO_REQUIRED');
    assert.equal(res.body.error.message, 'Snap a meal is part of FitSync Pro.');
  });

  await t.test('a new Pro user has the whole allowance and nothing to finish', async () => {
    const u = await freshUser({ pro: true });
    assert.deepEqual((await u.today().expect(200)).body, { data: { limit: 15, remainingToday: 15, unlogged: null } });
  });

  await t.test('only today\'s recognised photos count: not empty or failed ones, not yesterday\'s', async () => {
    const u = await freshUser({ pro: true });
    await rows(u.userId, 3, 'recognised');
    await rows(u.userId, 2, 'empty');
    await rows(u.userId, 4, 'failed');
    // The pool runs at +08:00: CURDATE() - 1 second is late yesterday in Manila.
    await rows(u.userId, 2, 'recognised', 'CURDATE() - INTERVAL 1 SECOND');
    const d = (await u.today().expect(200)).body.data;
    assert.deepEqual([d.limit, d.remainingToday], [15, 12]);
  });

  await t.test('more photos than the limit answers 0, never a negative number', async () => {
    const u = await freshUser({ pro: true });
    await rows(u.userId, 16, 'recognised');
    assert.equal((await u.today().expect(200)).body.data.remainingToday, 0);
  });
});
