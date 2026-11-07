'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { REGIONS } = require('../src/db/classify-contraindications');

const ROW_KEYS = [
  'animationUrl', 'equipment', 'id', 'muscleGroup', 'name', 'pendingReason', 'status', 'thumbnailUrl',
];

// Stands in for the storage driver: the database keeps keys, callers get URLs.
const storage = { url: (key) => `https://cdn.test/${key}` };

test('admin exercises endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool, storage });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth } = await createTestAdmin(pool);
  const get = (path) => request(app).get(`/api/v1/admin${path}`).set(auth);
  const list = async (query) => (await get(`/exercises${query}`).expect(200)).body.data;

  // The curated equipment the classifiers name, plus the catalogue tags used
  // below ('stationary bike' is in NICHE_EQUIPMENT).
  const equipmentIds = {};
  for (const name of ['bench', 'pull-up bar', 'machines', 'barbell', 'body weight', 'stationary bike']) {
    const [r] = await pool.query('INSERT INTO equipment (name) VALUES (?)', [name]);
    equipmentIds[name] = r.insertId;
  }
  // The 16 injury regions, as seed-injuries.js creates them.
  const injuryIds = {};
  for (const name of REGIONS) {
    const [r] = await pool.query(
      "INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, 'back_core')", [name],
    );
    injuryIds[name] = r.insertId;
  }

  let sourceNo = 0;
  const addExercise = async (name, muscleGroup, bodyPart, equipment, status) => {
    sourceNo += 1;
    const sourceId = String(sourceNo).padStart(4, '0');
    const [r] = await pool.query(
      `INSERT INTO exercises (source_id, name, muscle_group, body_part, equipment_id, animation_url, thumbnail_url, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [sourceId, name, muscleGroup, bodyPart, equipmentIds[equipment], `exercises/${sourceId}/animation.gif`,
        `exercises/${sourceId}/thumb.jpg`, status],
    );
    return { id: r.insertId, sourceId };
  };

  const jumpingJack = await addExercise('jumping jack', 'cardiovascular system', 'cardio', 'body weight', 'pending');
  const bike = await addExercise('stationary bike walk', 'quads', 'upper legs', 'stationary bike', 'pending');
  const incline = await addExercise('incline bench press', 'pectorals', 'chest', 'barbell', 'pending');
  const curl = await addExercise('barbell curl', 'biceps', 'upper arms', 'barbell', 'live');
  const pushUp = await addExercise('push-up', 'pectorals', 'chest', 'body weight', 'live');

  await t.test('a trainee token is refused', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('t@example.com', 'x', 'T')",
    );
    const token = signToken(u.insertId, TEST_JWT);
    const res = await request(app).get('/api/v1/admin/exercises?status=pending')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('status=pending lists only pending exercises, by name, with both counts', async () => {
    const data = await list('?status=pending');
    assert.deepEqual(data.exercises.map((e) => e.id), [incline.id, jumpingJack.id, bike.id]);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.deepEqual([data.page, data.limit, data.total], [1, 30, 3]);
  });

  await t.test('status=live lists only live exercises; counts stay the same', async () => {
    const data = await list('?status=live');
    assert.deepEqual(data.exercises.map((e) => e.id), [curl.id, pushUp.id]);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.equal(data.total, 2);
  });

  await t.test('a row carries URLs from storage, never keys', async () => {
    const [row] = (await list('?status=live&q=curl')).exercises;
    assert.deepEqual(Object.keys(row).sort(), ROW_KEYS);
    assert.deepEqual(row, {
      id: curl.id,
      name: 'barbell curl',
      muscleGroup: 'biceps',
      equipment: 'barbell',
      thumbnailUrl: `https://cdn.test/exercises/${curl.sourceId}/thumb.jpg`,
      animationUrl: `https://cdn.test/exercises/${curl.sourceId}/animation.gif`,
      status: 'live',
      pendingReason: null,
    });
  });

  await t.test('pendingReason says why a pending exercise was held back', async () => {
    const reasons = Object.fromEntries((await list('?status=pending')).exercises.map((e) => [e.id, e.pendingReason]));
    assert.deepEqual(reasons, { [jumpingJack.id]: 'cardio', [bike.id]: 'rare_equipment', [incline.id]: null });
  });

  await t.test('q matches the name, ignoring case; total follows it', async () => {
    const data = await list('?status=pending&q=BENCH');
    assert.deepEqual(data.exercises.map((e) => e.id), [incline.id]);
    assert.equal(data.total, 1);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.deepEqual((await list('?status=pending&q=%25')).exercises, []);
  });

  await t.test('page and limit pick a slice', async () => {
    const data = await list('?status=pending&page=2&limit=2');
    assert.deepEqual(data.exercises.map((e) => e.id), [bike.id]);
    assert.deepEqual([data.page, data.limit, data.total], [2, 2, 3]);
    assert.equal((await get('/exercises?status=pending&limit=51').expect(400)).body.error.code, 'INVALID_QUERY_PARAM');
  });

  await t.test('a missing or unknown status is 400 INVALID_ADMIN_FIELD', async () => {
    for (const query of ['', '?status=', '?status=all', '?status=live&status=pending']) {
      const res = await get(`/exercises${query}`).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', query);
      assert.deepEqual(res.body.error.details, [{ field: 'status' }], query);
    }
  });

});
