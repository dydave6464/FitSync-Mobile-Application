'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExerciseSafety } = require('../src/db/seed-exercise-safety');

test('exercise safety seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // The curated equipment rows the classifiers name.
  const equipmentIds = {};
  for (const name of ['bench', 'pull-up bar', 'machines', 'barbell', 'body weight']) {
    const [r] = await pool.query('INSERT INTO equipment (name) VALUES (?)', [name]);
    equipmentIds[name] = r.insertId;
  }
  // The 16 injury regions, as seed-injuries.js creates them. The seed resolves
  // classifier region names against these, so they must exist first.
  const { REGIONS } = require('../src/db/classify-contraindications');
  const injuryIds = {};
  for (const name of REGIONS) {
    const [r] = await pool.query(
      "INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, 'back_core')",
      [name],
    );
    injuryIds[name] = r.insertId;
  }
  const addExercise = async (name, muscleGroup, bodyPart, equipment) => {
    const [r] = await pool.query(
      `INSERT INTO exercises (name, muscle_group, body_part, equipment_id, status)
       VALUES (?, ?, ?, ?, 'live')`,
      [name, muscleGroup, bodyPart, equipment ? equipmentIds[equipment] : null],
    );
    return r.insertId;
  };

  const benchPress = await addExercise('barbell bench press', 'pectorals', 'chest', 'barbell');
  const pullUp = await addExercise('pull-up', 'lats', 'back', 'body weight');
  const curl = await addExercise('dumbbell seated biceps curl', 'biceps', 'upper arms', null);

  await t.test('a first run classifies the catalogue', async () => {
    const result = await seedExerciseSafety(testDbConfig());
    assert.ok(result.requirements.inserted > 0);
    assert.ok(result.contraindications.inserted > 0);

    const [reqs] = await pool.query(
      'SELECT equipment_id FROM exercise_equipment_requirements WHERE exercise_id = ?',
      [benchPress],
    );
    assert.deepEqual(reqs.map((r) => r.equipment_id), [equipmentIds.bench]);

    const [bar] = await pool.query(
      'SELECT equipment_id FROM exercise_equipment_requirements WHERE exercise_id = ?',
      [pullUp],
    );
    assert.deepEqual(bar.map((r) => r.equipment_id), [equipmentIds['pull-up bar']]);
  });

  await t.test('a spine-unsafe exercise is contraindicated, a safe one is not', async () => {
    const [unsafe] = await pool.query(
      'SELECT pattern FROM exercise_contraindications WHERE exercise_id = ? AND injury_id = ?',
      [pullUp, injuryIds['Lower back']],
    );
    assert.equal(unsafe.length, 1);
    assert.equal(unsafe[0].pattern, 'not_spine_safe');

    const [safe] = await pool.query(
      'SELECT 1 FROM exercise_contraindications WHERE exercise_id = ? AND injury_id = ?',
      [curl, injuryIds['Lower back']],
    );
    assert.equal(safe.length, 0);
  });

  await t.test('one exercise lands rows for several distinct regions', async () => {
    // This is what the region_group key could not express: a pull-up loads the
    // spine, the shoulder, the elbow and the grip, and each is its own row.
    const [rows] = await pool.query(
      `SELECT i.name FROM exercise_contraindications c
         JOIN injuries i ON i.injury_id = c.injury_id
        WHERE c.exercise_id = ? ORDER BY i.name`,
      [pullUp],
    );
    const names = rows.map((r) => r.name);
    for (const expected of ['Lower back', 'Shoulder', 'Elbow', 'Hand']) {
      assert.ok(names.includes(expected), `expected a ${expected} row, got ${names.join(', ')}`);
    }
  });

  await t.test('a second run changes nothing', async () => {
    const [before] = await pool.query('SELECT COUNT(*) AS n FROM exercise_contraindications');
    const result = await seedExerciseSafety(testDbConfig());
    const [after] = await pool.query('SELECT COUNT(*) AS n FROM exercise_contraindications');
    assert.equal(after[0].n, before[0].n);
    assert.equal(result.contraindications.inserted, 0);
    assert.equal(result.contraindications.removed, 0);
  });

  await t.test('a manual row survives a re-seed', async () => {
    // A reviewer decides the seated curl is unsafe for a back injury after all.
    await pool.query(
      `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern, is_manual)
       VALUES (?, ?, 'reviewer', 1)`,
      [curl, injuryIds['Lower back']],
    );
    const result = await seedExerciseSafety(testDbConfig());
    const [rows] = await pool.query(
      'SELECT pattern, is_manual FROM exercise_contraindications WHERE exercise_id = ? AND injury_id = ?',
      [curl, injuryIds['Lower back']],
    );
    assert.equal(rows.length, 1);
    assert.equal(rows[0].pattern, 'reviewer');
    assert.equal(rows[0].is_manual, 1);
    assert.equal(result.contraindications.manual, 1);
  });

  await t.test('a stale classifier row is removed when the exercise changes', async () => {
    // Rename it so the classifier no longer sees a bench.
    await pool.query('UPDATE exercises SET name = ? WHERE exercise_id = ?',
      ['barbell floor press', benchPress]);
    const result = await seedExerciseSafety(testDbConfig());
    assert.ok(result.requirements.removed >= 1);
    const [rows] = await pool.query(
      'SELECT 1 FROM exercise_equipment_requirements WHERE exercise_id = ?', [benchPress],
    );
    assert.equal(rows.length, 0);
  });

  await t.test('an unknown curated equipment name is reported, not thrown', async () => {
    await pool.query('DELETE FROM exercise_equipment_requirements WHERE equipment_id = ?',
      [equipmentIds['pull-up bar']]);
    await pool.query('DELETE FROM equipment WHERE equipment_id = ?', [equipmentIds['pull-up bar']]);
    const result = await seedExerciseSafety(testDbConfig());
    assert.ok(result.unknownEquipment.includes('pull-up bar'));
  });

  await t.test('a missing injury region is reported, not silently dropped', async () => {
    // seed-injuries.js not having run is the realistic cause. A dropped
    // contraindication is a safety row that never existed, so it must be loud.
    await pool.query('DELETE FROM exercise_contraindications WHERE injury_id = ?',
      [injuryIds.Shoulder]);
    await pool.query('DELETE FROM injuries WHERE injury_id = ?', [injuryIds.Shoulder]);
    const result = await seedExerciseSafety(testDbConfig());
    assert.ok(result.unknownRegions.includes('Shoulder'));
  });
});
