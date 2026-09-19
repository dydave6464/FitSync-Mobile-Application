'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('report endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  const app = buildTestApp({ pool, publicBaseUrl: 'https://fitsync.test' });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const freshUser = async (email) => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'Juan Dela Cruz' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { token: login.body.data.token, userId: res.body.data.user.userId };
  };

  const allSections = {
    volume: true, bodyWeight: true, muscles: true, sessions: true,
  };

  await t.test('creating a report answers a link and an expiry', async () => {
    const { token } = await freshUser('r1@example.com');

    const res = await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);

    assert.match(res.body.data.url, /^https:\/\/fitsync\.test\/api\/v1\/reports\/[A-Za-z0-9_-]{43}$/);
    assert.ok(Date.parse(res.body.data.expiresAt) > Date.now());
  });

  await t.test('an unknown period is refused', async () => {
    const { token } = await freshUser('r2@example.com');

    const res = await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'fortnight', include: allSections })
      .expect(400);

    assert.equal(res.body.error.code, 'INVALID_PERIOD');
  });

  // The Pro section must not reach the row for a free user. Checking the
  // stored snapshot rather than the response is the point: the response does
  // not carry the report.
  await t.test('a free user’s stored report holds no muscle section', async () => {
    const { token, userId } = await freshUser('r3@example.com');

    await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);

    const [[row]] = await pool.query(
      'SELECT report_json FROM shared_reports WHERE user_id = ?', [userId],
    );
    const json = typeof row.report_json === 'string'
      ? JSON.parse(row.report_json) : row.report_json;
    assert.equal(json.muscles, null);
  });

  await t.test('creating a report requires a token', async () => {
    await request(app).post('/api/v1/reports').send({ period: 'week' }).expect(401);
  });
});
