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

test('exercise endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const app = buildTestApp({
    pool,
    storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  // The catalogue now requires a signed-in caller. Create one user once and
  // reuse its token on every request below.
  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('t@example.com', 'x', 'T')",
  );
  const auth = `Bearer ${signToken(u.insertId, { secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h' })}`;

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('lists live exercises in the data envelope', async () => {
    const res = await request(app).get('/api/v1/exercises').set('Authorization', auth).expect(200);
    assert.ok(res.body.data, 'response must use the data envelope');
    assert.equal(res.body.data.total, 4);
    assert.equal(res.body.data.page, 1);
    assert.equal(res.body.data.limit, 20);
    assert.equal(res.body.data.exercises.length, 4);
  });

  await t.test('list items carry resolved URLs, not storage keys', async () => {
    const res = await request(app).get('/api/v1/exercises').set('Authorization', auth).expect(200);
    const item = res.body.data.exercises[0];
    assert.match(item.thumbnailUrl, /^\/storage\/exercises\//);
    assert.equal(item.animationUrl, undefined, 'list items must not carry the animation');
    assert.equal(typeof item.exerciseId, 'number');
    assert.equal(typeof item.muscleGroup, 'string');
  });

  await t.test('filters by muscle group and by equipment', async () => {
    const byMuscle = await request(app).get('/api/v1/exercises?muscleGroup=biceps').set('Authorization', auth).expect(200);
    assert.equal(byMuscle.body.data.total, 2);

    const byEquipment = await request(app).get('/api/v1/exercises?equipment=dumbbell').set('Authorization', auth).expect(200);
    assert.equal(byEquipment.body.data.total, 1);
  });

  await t.test('rejects a limit above the cap rather than clamping it', async () => {
    const res = await request(app).get('/api/v1/exercises?limit=500').set('Authorization', auth).expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    assert.match(res.body.error.message, /limit/);
    assert.equal(res.body.data, undefined);
  });

  await t.test('rejects a non-integer page', async () => {
    const res = await request(app).get('/api/v1/exercises?page=abc').set('Authorization', auth).expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
  });

  await t.test('rejects page zero', async () => {
    await request(app).get('/api/v1/exercises?page=0').set('Authorization', auth).expect(400);
  });

  await t.test('rejects a page value outside the safe integer range', async () => {
    const res = await request(app)
      .get('/api/v1/exercises?page=99999999999999999999')
      .set('Authorization', auth)
      .expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    assert.match(res.body.error.message, /page/);
    assert.equal(res.body.data, undefined);
  });

  await t.test('rejects a repeated muscleGroup query param instead of erroring on the array', async () => {
    const res = await request(app)
      .get('/api/v1/exercises?muscleGroup=abs&muscleGroup=biceps')
      .set('Authorization', auth)
      .expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    assert.match(res.body.error.message, /muscleGroup/);
    assert.equal(res.body.data, undefined);
  });

  await t.test('returns one exercise with cues and an animation', async () => {
    const list = await request(app).get('/api/v1/exercises').set('Authorization', auth).expect(200);
    const { exerciseId } = list.body.data.exercises[0];

    const res = await request(app).get(`/api/v1/exercises/${exerciseId}`).set('Authorization', auth).expect(200);
    assert.equal(res.body.data.exerciseId, exerciseId);
    assert.match(res.body.data.animationUrl, /^\/storage\/exercises\/.*\.gif$/);
    assert.ok(Array.isArray(res.body.data.cues));
    assert.ok(res.body.data.cues.length >= 1);
  });

  await t.test('an unknown id is a 404 in the error envelope', async () => {
    const res = await request(app).get('/api/v1/exercises/999999').set('Authorization', auth).expect(404);
    assert.equal(res.body.error.code, 'EXERCISE_NOT_FOUND');
    assert.ok(res.body.error.message);
  });

  await t.test('a pending exercise is a 404, not a leak', async () => {
    const [[pending]] = await pool.query(
      "SELECT exercise_id FROM exercises WHERE status = 'pending' LIMIT 1",
    );
    await request(app).get(`/api/v1/exercises/${pending.exercise_id}`).set('Authorization', auth).expect(404);
  });

  await t.test('a non-numeric id is a 400, not a 500', async () => {
    const res = await request(app).get('/api/v1/exercises/not-a-number').set('Authorization', auth).expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
  });

  await t.test('filters endpoint is not shadowed by the :id route', async () => {
    const res = await request(app).get('/api/v1/exercises/filters').set('Authorization', auth).expect(200);
    assert.ok(Array.isArray(res.body.data.muscleGroups));
    assert.ok(Array.isArray(res.body.data.equipment));
    const abs = res.body.data.muscleGroups.find((m) => m.value === 'abs');
    assert.equal(abs.count, 2);
  });

  await t.test('health still works — the new router did not break mounting', async () => {
    await request(app).get('/api/v1/health').expect(200);
  });
});
