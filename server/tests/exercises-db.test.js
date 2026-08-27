'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const {
  listExercises, getExerciseById, listFilters, DEFAULT_LIMIT, MAX_LIMIT,
} = require('../src/db/exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('exercise queries', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('lists only live exercises', async () => {
    const { rows, total } = await listExercises(pool, { page: 1, limit: 20 });
    // fixture has 5 exercises, one of them (0005, sled machine) is pending
    assert.equal(total, 4);
    assert.equal(rows.length, 4);
    assert.ok(!rows.some((r) => r.name === 'Sled push'), 'pending exercise must not appear');
  });

  await t.test('filters by muscle group', async () => {
    const { rows, total } = await listExercises(pool, { muscleGroup: 'biceps', page: 1, limit: 20 });
    assert.equal(total, 2);
    assert.ok(rows.every((r) => r.muscle_group === 'biceps'));
  });

  await t.test('filters by equipment', async () => {
    const { rows, total } = await listExercises(pool, { equipment: 'dumbbell', page: 1, limit: 20 });
    assert.equal(total, 1);
    assert.equal(rows[0].equipment, 'dumbbell');
  });

  await t.test('paginates with a stable order', async () => {
    const first = await listExercises(pool, { page: 1, limit: 2 });
    const second = await listExercises(pool, { page: 2, limit: 2 });
    assert.equal(first.rows.length, 2);
    assert.equal(second.rows.length, 2);
    assert.equal(first.total, 4);
    const ids = [...first.rows, ...second.rows].map((r) => r.exercise_id);
    assert.equal(new Set(ids).size, 4, 'pages must not overlap');
  });

  await t.test('a page past the end is empty, not an error', async () => {
    const { rows, total } = await listExercises(pool, { page: 99, limit: 20 });
    assert.deepEqual(rows, []);
    assert.equal(total, 4);
  });

  await t.test('returns storage keys, not resolved URLs', async () => {
    const { rows } = await listExercises(pool, { page: 1, limit: 1 });
    assert.match(rows[0].thumbnail_url, /^exercises\//, 'the query layer must not resolve URLs');
  });

  await t.test('detail includes cues in order', async () => {
    const { rows } = await listExercises(pool, { muscleGroup: 'abs', page: 1, limit: 1 });
    const row = await getExerciseById(pool, rows[0].exercise_id);
    assert.ok(row);
    assert.ok(Array.isArray(row.cues));
    assert.ok(row.cues.length >= 1);
    assert.equal(typeof row.animation_url, 'string');
  });

  await t.test('detail returns null for an unknown id', async () => {
    assert.equal(await getExerciseById(pool, 999999), null);
  });

  await t.test('detail returns null for a pending exercise', async () => {
    const [[pending]] = await pool.query(
      "SELECT exercise_id FROM exercises WHERE status = 'pending' LIMIT 1",
    );
    assert.ok(pending, 'fixture should contain a pending exercise');
    assert.equal(await getExerciseById(pool, pending.exercise_id), null);
  });

  await t.test('filters list distinct live values with counts', async () => {
    const { muscleGroups, equipment } = await listFilters(pool);
    const abs = muscleGroups.find((m) => m.value === 'abs');
    assert.equal(abs.count, 2);
    assert.ok(!equipment.some((e) => e.value === 'sled machine'),
      'equipment used only by pending exercises must not appear');
  });

  await t.test('exposes its limit constants', () => {
    assert.equal(DEFAULT_LIMIT, 20);
    assert.equal(MAX_LIMIT, 50);
  });
});
