'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('009 exercise safety schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const newExercise = async (name) => {
    const [r] = await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES (?, 'glutes', 'live')",
      [name],
    );
    return r.insertId;
  };
  const benchId = async () => {
    const [r] = await pool.query(
      "INSERT INTO equipment (name) VALUES ('bench') ON DUPLICATE KEY UPDATE equipment_id = LAST_INSERT_ID(equipment_id)",
    );
    return r.insertId;
  };
  // migrate() creates `injuries` empty; seed-injuries.js fills it in production.
  const injuryId = async (name) => {
    const [r] = await pool.query(
      `INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, 'back_core')
       ON DUPLICATE KEY UPDATE injury_id = LAST_INSERT_ID(injury_id)`,
      [name],
    );
    return r.insertId;
  };

  await t.test('creates both tables', async () => {
    const [rows] = await pool.query(
      `SELECT table_name AS t FROM information_schema.tables
        WHERE table_schema = ? AND table_name IN
        ('exercise_equipment_requirements','exercise_contraindications')`,
      [testDbConfig().database],
    );
    assert.equal(rows.length, 2);
  });

  await t.test('an exercise cannot require the same equipment twice', async () => {
    const ex = await newExercise('barbell bench press');
    const eq = await benchId();
    await pool.query(
      'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id) VALUES (?, ?)',
      [ex, eq],
    );
    await assert.rejects(
      () => pool.query(
        'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id) VALUES (?, ?)',
        [ex, eq],
      ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('deleting an exercise removes its requirements (CASCADE)', async () => {
    const ex = await newExercise('dumbbell incline fly');
    const eq = await benchId();
    await pool.query(
      'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id) VALUES (?, ?)',
      [ex, eq],
    );
    await pool.query('DELETE FROM exercises WHERE exercise_id = ?', [ex]);
    const [rows] = await pool.query(
      'SELECT 1 FROM exercise_equipment_requirements WHERE exercise_id = ?', [ex],
    );
    assert.equal(rows.length, 0);
  });

  await t.test('an exercise is contraindicated at most once per injury region', async () => {
    const ex = await newExercise('barbell deadlift');
    const injury = await injuryId('Lower back');
    await pool.query(
      "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, 'not_spine_safe')",
      [ex, injury],
    );
    await assert.rejects(
      () => pool.query(
        "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, 'hip_load')",
        [ex, injury],
      ),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('the same exercise may be contraindicated for several regions', async () => {
    // A back squat loads the spine, the knee and the hip. Under the old
    // region_group key these collapsed into one row and the detail was lost.
    const ex = await newExercise('barbell back squat');
    for (const [region, pattern] of [
      ['Lower back', 'not_spine_safe'], ['Knee', 'knee_load'], ['Hip', 'hip_load'],
    ]) {
      await pool.query(
        'INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, ?)',
        [ex, await injuryId(region), pattern],
      );
    }
    const [rows] = await pool.query(
      'SELECT 1 FROM exercise_contraindications WHERE exercise_id = ?', [ex],
    );
    assert.equal(rows.length, 3);
  });

  await t.test('a contraindication must name a real injury region', async () => {
    const ex = await newExercise('barbell overhead squat');
    await assert.rejects(
      () => pool.query(
        "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, 999999, 'x')",
        [ex],
      ),
      (err) => err.code === 'ER_NO_REFERENCED_ROW_2',
    );
  });

  await t.test('both tables default is_manual to 0', async () => {
    const ex = await newExercise('barbell romanian deadlift');
    await pool.query(
      "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, 'not_spine_safe')",
      [ex, await injuryId('Lower back')],
    );
    const [rows] = await pool.query(
      'SELECT is_manual FROM exercise_contraindications WHERE exercise_id = ?', [ex],
    );
    assert.equal(rows[0].is_manual, 0);

    // Also test exercise_equipment_requirements
    const eq = await benchId();
    await pool.query(
      'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id) VALUES (?, ?)',
      [ex, eq],
    );
    const [reqRows] = await pool.query(
      'SELECT is_manual FROM exercise_equipment_requirements WHERE exercise_id = ?', [ex],
    );
    assert.equal(reqRows[0].is_manual, 0);
  });

  await t.test('deleting equipment referenced by a requirement fails (RESTRICT)', async () => {
    const ex = await newExercise('leg press');
    const eq = await benchId();
    await pool.query(
      'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id) VALUES (?, ?)',
      [ex, eq],
    );
    await assert.rejects(
      () => pool.query('DELETE FROM equipment WHERE equipment_id = ?', [eq]),
      (err) => err.code === 'ER_ROW_IS_REFERENCED_2',
    );
  });
});
