'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

// Deep copy so a mutating test cannot leak into the next one.
const manifest = () => JSON.parse(JSON.stringify(FIXTURE));

test('exercise catalogue seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const reset = async () => {
    await pool.query('DELETE FROM coaching_cues');
    await pool.query('DELETE FROM exercises');
    await pool.query('DELETE FROM equipment');
  };

  await t.test('seeds equipment, exercises and cues from the manifest', async () => {
    await reset();
    const summary = await seedExercises(testDbConfig(), manifest());

    assert.equal(summary.equipment, 4, 'body weight, dumbbell, barbell, sled machine');
    assert.equal(summary.exercises, 5);
    assert.equal(summary.cues, 8);
    assert.equal(summary.skipped, 0);

    const [ex] = await pool.query('SELECT COUNT(*) AS n FROM exercises');
    assert.equal(ex[0].n, 5);
    const [cues] = await pool.query('SELECT COUNT(*) AS n FROM coaching_cues');
    assert.equal(cues[0].n, 8);
  });

  await t.test('equipment is resolved to a foreign key, not stored as text', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    const [rows] = await pool.query(
      `SELECT e.name AS equipment FROM exercises x
       JOIN equipment e ON e.equipment_id = x.equipment_id
       WHERE x.source_id = '0003'`,
    );
    assert.equal(rows[0].equipment, 'dumbbell');
  });

  await t.test('promoted exercises are live and the rest stay pending', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    const [live] = await pool.query(
      "SELECT source_id FROM exercises WHERE status = 'live' ORDER BY source_id",
    );
    assert.deepEqual(live.map((r) => r.source_id), ['0001', '0002', '0003', '0004']);
    const [pending] = await pool.query("SELECT source_id FROM exercises WHERE status = 'pending'");
    assert.deepEqual(pending.map((r) => r.source_id), ['0005']);
  });

  await t.test('cues are numbered from 1 in manifest order', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    const [rows] = await pool.query(
      `SELECT c.order_no, c.cue_text FROM coaching_cues c
       JOIN exercises x ON x.exercise_id = c.exercise_id
       WHERE x.source_id = '0001' ORDER BY c.order_no`,
    );
    assert.deepEqual(rows.map((r) => r.order_no), [1, 2, 3]);
    assert.equal(rows[0].cue_text, 'Lie flat on your back.');
    assert.equal(rows[2].cue_text, 'Lower slowly.');
  });

  await t.test('running the seed twice changes nothing — it is idempotent', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    await seedExercises(testDbConfig(), manifest());

    const [ex] = await pool.query('SELECT COUNT(*) AS n FROM exercises');
    assert.equal(ex[0].n, 5, 'a second run must not duplicate exercises');
    const [cues] = await pool.query('SELECT COUNT(*) AS n FROM coaching_cues');
    assert.equal(cues[0].n, 8, 'a second run must not accumulate cues');
    const [eq] = await pool.query('SELECT COUNT(*) AS n FROM equipment');
    assert.equal(eq[0].n, 4);
  });

  await t.test('a renamed upstream exercise updates in place', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    const [before] = await pool.query("SELECT exercise_id FROM exercises WHERE source_id = '0001'");

    const renamed = manifest();
    renamed.exercises[0].name = 'Three-quarter sit-up';
    await seedExercises(testDbConfig(), renamed);

    const [after] = await pool.query(
      "SELECT exercise_id, name FROM exercises WHERE source_id = '0001'",
    );
    assert.equal(after.length, 1, 'a rename must update, not insert a duplicate');
    assert.equal(after[0].name, 'Three-quarter sit-up');
    assert.equal(after[0].exercise_id, before[0].exercise_id, 'the row keeps its identity');
  });

  await t.test('re-seeding replaces cues rather than appending them', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());

    const shortened = manifest();
    shortened.exercises[0].cues = ['Only one cue now.'];
    await seedExercises(testDbConfig(), shortened);

    const [rows] = await pool.query(
      `SELECT c.cue_text FROM coaching_cues c
       JOIN exercises x ON x.exercise_id = c.exercise_id
       WHERE x.source_id = '0001' ORDER BY c.order_no`,
    );
    assert.deepEqual(rows.map((r) => r.cue_text), ['Only one cue now.']);
  });

  await t.test('an admin promotion survives a re-seed', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    await pool.query("UPDATE exercises SET status = 'live' WHERE source_id = '0005'");

    await seedExercises(testDbConfig(), manifest());

    const [rows] = await pool.query("SELECT status FROM exercises WHERE source_id = '0005'");
    assert.equal(rows[0].status, 'live', 're-seeding must not revert a review decision');
  });

  await t.test('two exercises sharing a name both insert', async () => {
    await reset();
    await seedExercises(testDbConfig(), manifest());
    const [rows] = await pool.query(
      "SELECT source_id FROM exercises WHERE name = 'Shared Name' ORDER BY source_id",
    );
    assert.deepEqual(rows.map((r) => r.source_id), ['0003', '0004']);
  });

  await t.test('an exercise whose media failed to download is skipped and counted', async () => {
    await reset();
    const withFailure = manifest();
    withFailure.exercises[1].animation_url = null;

    const summary = await seedExercises(testDbConfig(), withFailure);
    assert.equal(summary.skipped, 1);
    assert.equal(summary.exercises, 4);

    const [rows] = await pool.query("SELECT COUNT(*) AS n FROM exercises WHERE source_id = '0002'");
    assert.equal(rows[0].n, 0, 'an exercise with no animation must not enter the catalogue');
  });

  await t.test('a failure part-way through rolls the whole seed back', async () => {
    await reset();
    const broken = manifest();
    // muscle_group is NOT NULL, so this fails on the fourth exercise — after
    // three have already been inserted.
    broken.exercises[3].muscle_group = null;

    await assert.rejects(() => seedExercises(testDbConfig(), broken));

    const [ex] = await pool.query('SELECT COUNT(*) AS n FROM exercises');
    assert.equal(ex[0].n, 0, 'no exercise may survive a failed seed');
    const [cues] = await pool.query('SELECT COUNT(*) AS n FROM coaching_cues');
    assert.equal(cues[0].n, 0, 'no cue may survive a failed seed');
  });
});
