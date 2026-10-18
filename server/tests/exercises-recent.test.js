'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { createStorage } = require('../src/services/storage');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { signToken } = require('../src/lib/tokens');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('recent exercises', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const app = buildTestApp({
    pool,
    storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // The fixture holds four live exercises; the limit tests need more than the
  // cap of 30, so the rest are written here. Live, with a thumbnail key, so a
  // row reads the way a real catalogue row does.
  for (let i = 0; i < 36; i += 1) {
    await pool.query(
      `INSERT INTO exercises (name, muscle_group, thumbnail_url, status)
       VALUES (?, 'pectorals', ?, 'live')`,
      [`Extra ${String(i).padStart(2, '0')}`, `exercises/x${i}/thumb.jpg`],
    );
  }
  const [live] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status = 'live' ORDER BY exercise_id",
  );
  const liveIds = live.map((r) => r.exercise_id);
  const [[pending]] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status = 'pending' LIMIT 1",
  );

  let n = 0;
  const freshUser = async () => {
    n += 1;
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'R')",
      [`recent${n}@example.com`],
    );
    const token = signToken(u.insertId, {
      secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h',
    });
    return { userId: u.insertId, auth: `Bearer ${token}` };
  };

  /// A session holding one logged set per exercise, in the order given. Raw
  /// rows: this file is about what "recent" reads, not about the logging flow.
  const logSession = async (userId, exerciseIds, { status = 'completed', daysAgo = 0 } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, plan_id, status, session_date, started_at)
       VALUES (?, NULL, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY), NOW())`,
      [userId, status, daysAgo],
    );
    for (const id of exerciseIds) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, 1, 20, 10, TRUE)`,
        [s.insertId, id],
      );
    }
    return s.insertId;
  };

  const recent = async (auth, query = '', status = 200) => {
    const res = await request(app).get(`/api/v1/exercises/recent${query}`)
      .set('Authorization', auth).expect(status);
    return res.body;
  };
  const ids = (body) => body.data.exercises.map((e) => e.exerciseId);

  await t.test('nothing logged yet is an empty list, not an error', async () => {
    const u = await freshUser();
    const body = await recent(u.auth);
    assert.deepEqual(body.data.exercises, []);
  });

  await t.test('is not mistaken for an exercise id', async () => {
    // Registered after '/:id', 'recent' would reach the id parser and come
    // back as a 400 about a positive integer.
    const u = await freshUser();
    const body = await recent(u.auth);
    assert.ok(Array.isArray(body.data.exercises));
  });

  await t.test('newest first, each exercise once', async () => {
    const u = await freshUser();
    const [a, b, c] = liveIds;
    await logSession(u.userId, [a, b], { daysAgo: 3 });
    await logSession(u.userId, [c, a], { daysAgo: 1 });
    await logSession(u.userId, [b], { daysAgo: 0 });

    // b today; then the session one day ago, whose later set is a; then c.
    assert.deepEqual(ids(await recent(u.auth)), [b, a, c]);
  });

  await t.test("today's in-progress workout counts", async () => {
    const u = await freshUser();
    const [a, b] = liveIds;
    await logSession(u.userId, [a], { daysAgo: 2 });
    await logSession(u.userId, [b], { status: 'in_progress' });
    assert.deepEqual(ids(await recent(u.auth)), [b, a]);
  });

  await t.test('an abandoned session is ignored', async () => {
    const u = await freshUser();
    const [a, b] = liveIds;
    await logSession(u.userId, [a], { daysAgo: 2 });
    await logSession(u.userId, [b], { status: 'abandoned' });
    assert.deepEqual(ids(await recent(u.auth)), [a]);
  });

  await t.test('an unticked set row is not a logged set', async () => {
    const u = await freshUser();
    const [a, b] = liveIds;
    await logSession(u.userId, [a], { daysAgo: 1 });
    const s = await logSession(u.userId, []);
    await pool.query(
      'INSERT INTO set_logs (session_id, exercise_id, set_number, is_completed) VALUES (?, ?, 1, FALSE)',
      [s, b],
    );
    assert.deepEqual(ids(await recent(u.auth)), [a]);
  });

  await t.test("another account's sets never appear", async () => {
    const mine = await freshUser();
    const theirs = await freshUser();
    await logSession(theirs.userId, [liveIds[0], liveIds[1]]);
    await logSession(mine.userId, [liveIds[2]], { daysAgo: 5 });
    assert.deepEqual(ids(await recent(mine.auth)), [liveIds[2]]);
  });

  await t.test('an exercise the catalogue does not show is left out', async () => {
    // Demoted to pending, or never reviewed: the list route would not show it,
    // so a strip of shortcuts into that list must not either.
    const u = await freshUser();
    await logSession(u.userId, [liveIds[0]], { daysAgo: 1 });
    await logSession(u.userId, [pending.exercise_id]);
    assert.deepEqual(ids(await recent(u.auth)), [liveIds[0]]);
  });

  await t.test('rows have the list shape, flagged for the caller', async () => {
    const u = await freshUser();
    const other = await freshUser();
    const [a, b] = liveIds;
    const [inj] = await pool.query(
      "INSERT INTO injuries (name, is_lateral, region_group) VALUES (CONCAT('Region ', UUID()), 0, 'back')",
    );
    await pool.query(
      'INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, ?)',
      [a, inj.insertId, 'test_pattern'],
    );
    await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)', [u.userId, inj.insertId]);
    await logSession(u.userId, [a, b]);
    await logSession(other.userId, [a, b]);

    const [row] = (await recent(u.auth)).data.exercises.filter((e) => e.exerciseId === a);
    assert.deepEqual(
      Object.keys(row).sort(),
      ['contraindicated', 'equipment', 'exerciseId', 'muscleGroup', 'name', 'thumbnailUrl'],
    );
    assert.equal(row.contraindicated, true);
    assert.match(row.thumbnailUrl, /^\/storage\/exercises\//);
    const [unflagged] = (await recent(u.auth)).data.exercises.filter((e) => e.exerciseId === b);
    assert.equal(unflagged.contraindicated, false);

    // The same exercise, asked for by someone without that injury.
    const [theirs] = (await recent(other.auth)).data.exercises.filter((e) => e.exerciseId === a);
    assert.equal(theirs.contraindicated, false);
  });

  await t.test('ten by default, the limit when given, thirty at most', async () => {
    const u = await freshUser();
    await logSession(u.userId, liveIds.slice(0, 35));

    assert.equal((await recent(u.auth)).data.exercises.length, 10);
    assert.equal((await recent(u.auth, '?limit=3')).data.exercises.length, 3);
    assert.equal((await recent(u.auth, '?limit=30')).data.exercises.length, 30);

    const tooMany = await recent(u.auth, '?limit=31', 400);
    assert.equal(tooMany.error.code, 'INVALID_QUERY_PARAM');
    for (const bad of ['0', '-1', 'abc', '2.5']) {
      const body = await recent(u.auth, `?limit=${bad}`, 400);
      assert.equal(body.error.code, 'INVALID_QUERY_PARAM');
      assert.deepEqual(body.error.details, [{ field: 'limit', value: bad }]);
    }
  });

  await t.test('needs a signed-in caller', async () => {
    await request(app).get('/api/v1/exercises/recent').expect(401);
  });
});
