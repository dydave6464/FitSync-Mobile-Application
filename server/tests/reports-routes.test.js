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

  // The window bounds must be the server's LOCAL calendar day: that is the
  // basis report-snapshot.js's readers window their data on, via MySQL
  // CURDATE(). A UTC-based read (Date#toISOString) is a full day behind the
  // local calendar day for the first eight hours of every Asia/Manila day --
  // reproduced here at a fixed instant so the test does not depend on what
  // time it happens to run.
  await t.test('the report window is the server-local calendar day, not UTC', async (t) => {
    const { token, userId } = await freshUser('r4@example.com');

    // 2026-01-01T00:30 in Asia/Manila (UTC+8) is 2025-12-31T16:30 UTC: a
    // UTC read reports the day before the local calendar day at this instant.
    t.mock.timers.enable({ apis: ['Date'] });
    t.mock.timers.setTime(Date.UTC(2025, 11, 31, 16, 30, 0));

    await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);

    t.mock.timers.reset();

    const [[row]] = await pool.query(
      'SELECT window_start, window_end FROM shared_reports WHERE user_id = ?', [userId],
    );
    const dateOnly = (d) => d.toISOString().slice(0, 10);
    assert.equal(dateOnly(row.window_end), '2026-01-01');
    assert.equal(dateOnly(row.window_start), '2025-12-25');
  });

  // Comparing against MySQL's own CURDATE() rather than against a
  // JS-computed expectation checks the real authority: CURDATE() is exactly
  // the function report-snapshot.js's readers window their data with, so
  // this is the actual invariant a shared report depends on, not our own
  // arithmetic re-derived a second time.
  await t.test('the report window matches what CURDATE() calls today', async () => {
    const { token, userId } = await freshUser('r5@example.com');

    await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);

    const [[row]] = await pool.query(
      `SELECT DATEDIFF(window_end, window_start) AS span,
              window_end = CURDATE() AS ends_today
         FROM shared_reports WHERE user_id = ?`, [userId],
    );
    assert.equal(row.span, 7);
    assert.equal(row.ends_today, 1);
  });

  await t.test('creating a report requires a token', async () => {
    await request(app).post('/api/v1/reports').send({ period: 'week' }).expect(401);
  });

  const shareFor = async (email) => {
    const { token, userId } = await freshUser(email);
    const res = await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);
    return { url: res.body.data.url, userId, path: new URL(res.body.data.url).pathname };
  };

  await t.test('the link renders a page naming who shared it', async () => {
    const { path } = await shareFor('p1@example.com');

    const res = await request(app).get(path).expect(200);
    assert.match(res.headers['content-type'], /text\/html/);
    assert.match(res.text, /Juan Dela Cruz/);
  });

  // A pasted link must not end up in a search index.
  await t.test('the page refuses indexing', async () => {
    const { path } = await shareFor('p2@example.com');

    const res = await request(app).get(path).expect(200);
    assert.match(res.headers['x-robots-tag'], /noindex/);
  });

  await t.test('an expired link stops working', async () => {
    const { path, userId } = await shareFor('p3@example.com');
    await pool.query(
      'UPDATE shared_reports SET expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE user_id = ?',
      [userId],
    );

    const res = await request(app).get(path).expect(404);
    assert.match(res.text, /no longer available/i);
  });

  // Expired and never-existed render the same page, so the endpoint does not
  // confirm whether a token was ever real.
  await t.test('an unknown link is indistinguishable from an expired one', async () => {
    const { path, userId } = await shareFor('p4@example.com');
    await pool.query(
      'UPDATE shared_reports SET expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE user_id = ?',
      [userId],
    );

    const expired = await request(app).get(path).expect(404);
    const unknown = await request(app)
      .get(`/api/v1/reports/${'z'.repeat(43)}`).expect(404);
    assert.equal(expired.text, unknown.text);
  });

  // The name is interpolated into HTML and comes from user input.
  await t.test('a hostile display name cannot inject markup', async () => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({
        email: 'xss@example.com',
        password: 's3cret-pass',
        fullName: '<script>alert(1)</script>',
      }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'xss@example.com', password: 's3cret-pass' }).expect(200);
    const created = await request(app).post('/api/v1/reports')
      .set('Authorization', `Bearer ${login.body.data.token}`)
      .send({ period: 'week', include: allSections })
      .expect(201);

    const page = await request(app)
      .get(new URL(created.body.data.url).pathname).expect(200);
    assert.ok(!page.text.includes('<script>alert(1)</script>'));
    assert.match(page.text, /&lt;script&gt;/);
  });

  await t.test('reading a report needs no token of its own', async () => {
    const { path } = await shareFor('p5@example.com');
    await request(app).get(path).expect(200);
  });
});
