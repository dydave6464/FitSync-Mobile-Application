'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('session_exercises schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('cascades from its session and restricts its exercise', async () => {
    // Copied from set_logs on purpose: deleting a session takes its list with
    // it, and a catalogue row cannot vanish out from under logged history.
    const [rows] = await pool.query(
      `SELECT rc.constraint_name AS name, rc.delete_rule AS onDelete,
              k.referenced_table_name AS refTable
         FROM information_schema.referential_constraints rc
         JOIN information_schema.key_column_usage k
           ON k.constraint_name = rc.constraint_name
          AND k.constraint_schema = rc.constraint_schema
        WHERE rc.constraint_schema = ? AND rc.table_name = 'session_exercises'`,
      [testDbConfig().database],
    );
    const byTable = Object.fromEntries(rows.map((r) => [r.refTable, r.onDelete]));
    assert.equal(byTable.workout_sessions, 'CASCADE');
    assert.equal(byTable.exercises, 'RESTRICT');
  });

  await t.test('holds an exercise at most once per session', async () => {
    const [rows] = await pool.query(
      `SELECT index_name AS name, non_unique AS nonUnique, column_name AS col
         FROM information_schema.statistics
        WHERE table_schema = ? AND table_name = 'session_exercises'
        ORDER BY index_name, seq_in_index`,
      [testDbConfig().database],
    );
    const unique = rows.filter((r) => r.name === 'uq_session_exercises');
    assert.deepEqual(unique.map((r) => r.col), ['session_id', 'exercise_id']);
    assert.equal(Number(unique[0].nonUnique), 0);
  });

  await t.test('orders a session list by order_no', async () => {
    const [rows] = await pool.query(
      `SELECT column_name AS col
         FROM information_schema.statistics
        WHERE table_schema = ? AND table_name = 'session_exercises'
          AND index_name = 'idx_session_exercises_session'
        ORDER BY seq_in_index`,
      [testDbConfig().database],
    );
    assert.deepEqual(rows.map((r) => r.col), ['session_id', 'order_no']);
  });

  await t.test('target_reps is a string, because ranges are', async () => {
    // plan_exercises.target_reps is VARCHAR for the same reason: the
    // generator writes "8-12". Typing it as an int crashes on every real row.
    const [rows] = await pool.query(
      `SELECT data_type AS type FROM information_schema.columns
        WHERE table_schema = ? AND table_name = 'session_exercises'
          AND column_name = 'target_reps'`,
      [testDbConfig().database],
    );
    assert.equal(rows[0].type, 'varchar');
  });
});
