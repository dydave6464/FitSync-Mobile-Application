'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { createCueService } = require('../src/services/cues');
const { signToken } = require('../src/lib/tokens');

const SECRET = 'test-secret-value-at-least-32-chars';

test('GET /exercises/:id/cues', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  const app = buildTestApp({ pool, cues: createCueService({ mode: 'stub' }) });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('r@example.com','x','R')",
  );
  const auth = `Bearer ${signToken(u.insertId, { secret: SECRET, expiresIn: '1h' })}`;

  const [press] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Overhead Press','delts','live')",
  );
  await pool.query(
    'INSERT INTO coaching_cues (exercise_id, order_no, cue_text) VALUES (?, 1, ?)',
    [press.insertId, 'Brace before you press.'],
  );

  const [pending] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Not Live Yet','delts','pending')",
  );

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('requires a signed-in caller', async () => {
    await request(app).get(`/api/v1/exercises/${press.insertId}/cues`).expect(401);
  });

  await t.test('serves catalogue cues for an uninjured user', async () => {
    const res = await request(app)
      .get(`/api/v1/exercises/${press.insertId}/cues`)
      .set('Authorization', auth)
      .expect(200);

    assert.equal(res.body.data.source, 'catalogue');
    assert.equal(res.body.data.injury, null);
    assert.equal(res.body.data.cues.length, 1);
    assert.equal(res.body.data.cues[0].title, 'Brace before you press.');
    assert.equal(res.body.data.cues[0].detail, null);
  });

  await t.test('serves AI cues once the exercise loads a reported injury',
    async () => {
      const [rows] = await pool.query(
        "SELECT injury_id FROM injuries WHERE name = 'Shoulder'",
      );
      await pool.query(
        'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
        [u.insertId, rows[0].injury_id],
      );

      const res = await request(app)
        .get(`/api/v1/exercises/${press.insertId}/cues`)
        .set('Authorization', auth)
        .expect(200);

      assert.equal(res.body.data.source, 'ai');
      assert.equal(res.body.data.injury.name, 'Shoulder');
      assert.equal(res.body.data.injury.reason, 'trains_region');
      assert.equal(typeof res.body.data.injury.injuryId, 'number');
      // The stub names the injury it was asked about, which proves the gate's
      // finding reached the generator rather than a default.
      assert.match(res.body.data.cues[0].title, /Shoulder/);
      assert.equal(typeof res.body.data.cues[0].detail, 'string');
    });

  await t.test('404s for an exercise that does not exist', async () => {
    const res = await request(app)
      .get('/api/v1/exercises/999999/cues')
      .set('Authorization', auth)
      .expect(404);
    assert.equal(res.body.error.code, 'EXERCISE_NOT_FOUND');
  });

  // The catalogue endpoint hides non-live rows; this one must agree with it,
  // or an unreviewed exercise leaks through a side door.
  await t.test('404s for an exercise that is not live', async () => {
    await request(app)
      .get(`/api/v1/exercises/${pending.insertId}/cues`)
      .set('Authorization', auth)
      .expect(404);
  });

  await t.test('rejects a non-numeric id rather than treating it as one',
    async () => {
      const res = await request(app)
        .get('/api/v1/exercises/abc/cues')
        .set('Authorization', auth)
        .expect(400);
      assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    });

  // Belt and braces on the money question: a request for cues must never take
  // the whole catalogue endpoint down with it if the service is missing.
  await t.test('works even when no cue service was wired in', async () => {
    const bare = buildTestApp({ pool });
    const res = await request(bare)
      .get(`/api/v1/exercises/${press.insertId}/cues`)
      .set('Authorization', auth)
      .expect(200);

    assert.ok(['ai', 'catalogue'].includes(res.body.data.source));
  });
});
