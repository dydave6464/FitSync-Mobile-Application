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

  // A user with one injury, and the contraindication that blocks one of the
  // fixture's exercises for it.
  const seedInjured = async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    const [inj] = await pool.query(
      "INSERT INTO injuries (name, is_lateral, region_group) VALUES (CONCAT('Region ', UUID()), 0, 'back')",
    );
    await pool.query(
      'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [u.insertId, inj.insertId],
    );
    const [live] = await pool.query(
      "SELECT exercise_id FROM exercises WHERE status = 'live' ORDER BY exercise_id LIMIT 1",
    );
    await pool.query(
      'INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, ?)',
      [live[0].exercise_id, inj.insertId, 'test_pattern'],
    );
    return { userId: u.insertId, blockedId: live[0].exercise_id };
  };

  await t.test('marks the exercises that load a reported injury', async () => {
    // The generator already refuses these; the library let someone pick one
    // by hand with nothing said, which is the one place manual logging was
    // less safe than a generated plan.
    const { userId, blockedId } = await seedInjured();

    const { rows } = await listExercises(pool, { page: 1, limit: 20, userId });

    const blocked = rows.find((r) => r.exercise_id === blockedId);
    assert.equal(Boolean(blocked.contraindicated), true);
    const others = rows.filter((r) => r.exercise_id !== blockedId);
    assert.ok(others.length > 0, 'the fixture must offer something safe too');
    assert.ok(others.every((r) => !r.contraindicated));
  });

  await t.test('marks nothing for someone who reported no injuries', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );

    const { rows } = await listExercises(pool, { page: 1, limit: 20, userId: u.insertId });

    assert.ok(rows.every((r) => !r.contraindicated));
  });

  await t.test('marking changes neither the rows nor the total', async () => {
    // A flag, not a filter. Hiding 608 rows with no explanation reads as a
    // broken search, and the count has to keep describing the catalogue.
    const { userId } = await seedInjured();

    const anon = await listExercises(pool, { page: 1, limit: 20 });
    const mine = await listExercises(pool, { page: 1, limit: 20, userId });

    assert.equal(mine.total, anon.total);
    assert.deepEqual(
      mine.rows.map((r) => r.exercise_id),
      anon.rows.map((r) => r.exercise_id),
    );
  });

  await t.test('the flag survives a muscle-group filter', async () => {
    // The user id binds in the SELECT list and the filter binds in the WHERE,
    // so the two sets of parameters have to be ordered correctly. Swapped,
    // the filter silently matches on a user id instead of erroring.
    const { userId, blockedId } = await seedInjured();
    const [[blocked]] = await pool.query(
      'SELECT muscle_group FROM exercises WHERE exercise_id = ?', [blockedId],
    );

    const { rows } = await listExercises(pool, {
      page: 1, limit: 20, userId, muscleGroup: blocked.muscle_group,
    });

    assert.ok(rows.length > 0, 'the filter must still match its group');
    assert.ok(rows.every((r) => r.muscle_group === blocked.muscle_group));
    assert.equal(Boolean(rows.find((r) => r.exercise_id === blockedId).contraindicated), true);
  });

  await t.test('the detail view agrees with the list', async () => {
    const { userId, blockedId } = await seedInjured();

    const row = await getExerciseById(pool, blockedId, userId);

    assert.equal(Boolean(row.contraindicated), true);
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
