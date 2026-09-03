'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExerciseCategories } = require('../src/db/seed-exercise-categories');

test('exercise categories seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const add = async (name) => {
    const [r] = await pool.query(
      `INSERT INTO exercises (name, muscle_group, body_part, status)
       VALUES (?, 'abs', 'waist', 'live')`, [name],
    );
    return r.insertId;
  };
  const press = await add('barbell bench press');
  const stretch = await add('back pec stretch');
  const circles = await add('ankle circles');
  const lever = await add('back lever');
  const machine = await add('lever alternate leg press');

  const catOf = async (id) => {
    const [rows] = await pool.query(
      'SELECT category FROM exercise_categories WHERE exercise_id = ?', [id],
    );
    return rows.length ? rows[0].category : null;
  };

  await t.test('assigns a category to every live exercise', async () => {
    const result = await seedExerciseCategories(testDbConfig());
    assert.equal(result.inserted, 5);
    assert.equal(result.removed, 0);
    assert.equal(await catOf(press), 'strength');
    assert.equal(await catOf(stretch), 'stretch');
    assert.equal(await catOf(circles), 'mobility');
    assert.equal(await catOf(lever), 'other');
    assert.equal(await catOf(machine), 'strength', 'the machine prefix is not a hold');
  });

  await t.test('is idempotent', async () => {
    const result = await seedExerciseCategories(testDbConfig());
    assert.equal(result.inserted, 0);
    assert.equal(result.removed, 0);
  });

  await t.test('reports the per-category counts', async () => {
    const result = await seedExerciseCategories(testDbConfig());
    assert.deepEqual(result.counts, {
      strength: 2, stretch: 1, mobility: 1, other: 1,
    });
  });

  await t.test('never overwrites a manual row, even to a different category', async () => {
    // The primary-key case: the human says 'other', the classifier says
    // 'stretch'. Blocking on (exercise_id, category) would not filter this and
    // the INSERT would collide on the primary key.
    await pool.query(
      'UPDATE exercise_categories SET category = ?, is_manual = 1 WHERE exercise_id = ?',
      ['other', stretch],
    );
    const result = await seedExerciseCategories(testDbConfig());
    assert.equal(await catOf(stretch), 'other', 'the human judgement survived');
    assert.equal(result.manual, 1);
  });

  await t.test('a non-live exercise gets no category row', async () => {
    const [r] = await pool.query(
      `INSERT INTO exercises (name, muscle_group, body_part, status)
       VALUES ('pending thing', 'abs', 'waist', 'pending')`,
    );
    await seedExerciseCategories(testDbConfig());
    assert.equal(await catOf(r.insertId), null);
  });
});
