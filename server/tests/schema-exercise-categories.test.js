'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('exercise_categories schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [cols] = await pool.query(
    `SELECT column_name AS c, column_type AS t, is_nullable AS n, column_key AS k
       FROM information_schema.columns
      WHERE table_schema = ? AND table_name = 'exercise_categories'`,
    [testDbConfig().database],
  );
  const by = Object.fromEntries(cols.map((r) => [r.c, r]));

  assert.ok(by.exercise_id, 'exercise_id column exists');
  assert.equal(by.exercise_id.k, 'PRI', 'exercise_id is the primary key');
  assert.equal(
    by.category.t,
    "enum('strength','stretch','mobility','other')",
    'exactly four categories, no cardio',
  );
  assert.equal(by.category.n, 'NO');
  assert.equal(by.is_manual.t, 'tinyint(1)');
});

test('a category row is removed when its exercise is deleted', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [ex] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, body_part, status) VALUES ('t','abs','waist','live')",
  );
  await pool.query(
    'INSERT INTO exercise_categories (exercise_id, category) VALUES (?, ?)',
    [ex.insertId, 'stretch'],
  );
  await pool.query('DELETE FROM exercises WHERE exercise_id = ?', [ex.insertId]);
  const [rows] = await pool.query(
    'SELECT 1 FROM exercise_categories WHERE exercise_id = ?', [ex.insertId],
  );
  assert.equal(rows.length, 0, 'ON DELETE CASCADE removed the category row');
});
