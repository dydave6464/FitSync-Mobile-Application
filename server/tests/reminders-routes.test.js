'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

test('reminder settings endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `rr${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'R' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      get: () => request(app).get('/api/v1/reminders/settings').set(auth),
      patch: (b) => request(app).patch('/api/v1/reminders/settings').set(auth).send(b),
    };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/reminders/settings').expect(401);
    await request(app).patch('/api/v1/reminders/settings').send({}).expect(401);
  });

  await t.test('a new account reads the defaults', async () => {
    const res = await (await freshUser()).get().expect(200);
    assert.deepEqual(res.body, {
      data: {
        settings: {
          habitsEnabled: true, habitLeadMin: 15,
          workoutEnabled: false, workoutTime: '07:00',
          checkinEnabled: false, checkinTime: '07:00',
        },
      },
    });
  });

  await t.test('a patch changes only what is sent; unknown keys are dropped', async () => {
    const u = await freshUser();
    const res = await u.patch({ checkinEnabled: true, checkinTime: '06:15', surprise: 1 }).expect(200);
    assert.equal(res.body.data.settings.checkinEnabled, true);
    assert.equal(res.body.data.settings.checkinTime, '06:15');
    assert.equal(res.body.data.settings.habitsEnabled, true);
    assert.equal((await u.get().expect(200)).body.data.settings.checkinTime, '06:15');
  });

  await t.test('bad values are refused with a named code', async () => {
    const u = await freshUser();
    for (const [body, code] of [
      [{ habitsEnabled: 'yes' }, 'REMINDER_INVALID'],
      [{ workoutEnabled: 1 }, 'REMINDER_INVALID'],
      [{ habitLeadMin: 10 }, 'LEAD_INVALID'],
      [{ habitLeadMin: '15' }, 'LEAD_INVALID'],
      [{ workoutTime: '7:00' }, 'TIME_INVALID'],
      [{ checkinTime: '24:00' }, 'TIME_INVALID'],
    ]) {
      const res = await u.patch(body).expect(400);
      assert.equal(res.body.error.code, code, JSON.stringify(body));
    }
  });
});
