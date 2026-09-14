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
const { seedEquipment } = require('../src/db/seed-equipment');
const { signToken } = require('../src/lib/tokens');

/// One exercise per tag, deliberately spanning all three cases the rollup has
/// to handle: a curated parent tag ('barbell'), two of its hidden children
/// ('ez barbell', 'trap bar'), and a tag curation never adopted
/// ('medicine ball').
const MANIFEST = {
  source: { repo: 'test', commit: 'test', exercise_count: 5 },
  failures: [],
  exercises: [
    ['0001', 'Barbell curl', 'biceps', 'barbell'],
    ['0002', 'EZ bar curl', 'biceps', 'ez barbell'],
    ['0003', 'Trap bar deadlift', 'legs', 'trap bar'],
    ['0004', 'Cable fly', 'chest', 'cable'],
    ['0005', 'Medicine ball slam', 'abs', 'medicine ball'],
  ].map(([source_id, name, muscle_group, equipment]) => ({
    source_id,
    name,
    muscle_group,
    equipment,
    animation_url: `exercises/${source_id}/animation.gif`,
    thumbnail_url: `exercises/${source_id}/thumb.jpg`,
    promote: true,
    cues: ['Do the thing.'],
  })),
};

test('the catalogue filters by the equipment names onboarding uses', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  // Order matters: the catalogue seed creates the raw tags, and the equipment
  // seed is what adopts them under a curated parent.
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(MANIFEST)));
  await seedEquipment(testDbConfig());

  const app = buildTestApp({
    pool,
    storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('r@example.com', 'x', 'R')",
  );
  const auth = `Bearer ${signToken(u.insertId, {
    secret: 'test-secret-value-at-least-32-chars',
    expiresIn: '1h',
  })}`;

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const filters = async () => {
    const res = await request(app)
      .get('/api/v1/exercises/filters')
      .set('Authorization', auth)
      .expect(200);
    return res.body.data.equipment;
  };

  const listBy = async (equipment) => {
    const res = await request(app)
      .get(`/api/v1/exercises?equipment=${encodeURIComponent(equipment)}`)
      .set('Authorization', auth)
      .expect(200);
    return res.body.data.exercises.map((e) => e.name).sort();
  };

  await t.test('a child tag is counted under its curated parent', async () => {
    // barbell + ez barbell + trap bar. Offering all three separately is what
    // made the filter unusable: the user picks gear, not dataset vocabulary.
    const barbell = (await filters()).find((e) => e.value === 'barbell');
    assert.ok(barbell, 'barbell must be offered');
    assert.equal(barbell.count, 3);
  });

  await t.test('a child tag is not offered on its own', async () => {
    const values = (await filters()).map((e) => e.value);
    assert.ok(!values.includes('ez barbell'));
    assert.ok(!values.includes('trap bar'));
    assert.ok(!values.includes('cable'));
  });

  await t.test('each option carries the label onboarding shows', async () => {
    const byValue = new Map((await filters()).map((e) => [e.value, e.label]));
    assert.equal(byValue.get('barbell'), 'Barbell');
    assert.equal(byValue.get('machines'), 'Machines');
  });

  await t.test('a tag curation never adopted is still offered', async () => {
    // 13 medicine-ball exercises exist in the real catalogue. Dropping them
    // from the filter would make them reachable only by typing a name.
    const ball = (await filters()).find((e) => e.value === 'medicine ball');
    assert.ok(ball, 'an unadopted tag must not vanish from the filter');
    assert.equal(ball.count, 1);
    assert.equal(ball.label, 'Medicine ball',
      'an unadopted tag is titled for display, not shown raw');
  });

  await t.test('filtering by a parent returns its children too', async () => {
    assert.deepEqual(await listBy('barbell'),
      ['Barbell curl', 'EZ bar curl', 'Trap bar deadlift']);
  });

  await t.test('a parent with no tag of its own still returns its children',
    async () => {
      // Nothing is tagged 'machines'; it exists only as a parent. Matching on
      // the exercise's own tag alone would return nothing here.
      assert.deepEqual(await listBy('machines'), ['Cable fly']);
    });

  await t.test('filtering by an unadopted tag returns its own rows', async () => {
    assert.deepEqual(await listBy('medicine ball'), ['Medicine ball slam']);
  });

  await t.test('counts still add up to the catalogue', async () => {
    const total = (await filters()).reduce((sum, e) => sum + e.count, 0);
    assert.equal(total, 5, 'every exercise lands in exactly one bucket');
  });
});
