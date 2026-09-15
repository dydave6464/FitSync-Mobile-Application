'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('exercise_ai_cues schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('carries one cue per row, ordered', async () => {
    const [cols] = await pool.query('SHOW COLUMNS FROM exercise_ai_cues');
    const names = cols.map((c) => c.Field);
    for (const expected of [
      'ai_cue_id', 'exercise_id', 'injury_id', 'order_no',
      'title', 'detail', 'model', 'generated_at',
    ]) {
      assert.ok(names.includes(expected), `missing column ${expected}`);
    }
  });

  // The cache key. Without it a retry after a partial write doubles every cue,
  // and the table has no expiry to correct itself.
  await t.test('one row per exercise, injury and position', async () => {
    const [keys] = await pool.query(
      'SHOW INDEX FROM exercise_ai_cues WHERE Key_name = "uq_eac"',
    );
    assert.equal(keys.length, 3);
    assert.equal(keys[0].Non_unique, 0);
    assert.deepEqual(keys.map((k) => k.Column_name),
      ['exercise_id', 'injury_id', 'order_no']);
  });

  // Cues describe a movement and a joint. If either row goes, the advice
  // written about it is meaningless -- it must not outlive its subject.
  await t.test('cues die with the exercise or the injury they describe',
    async () => {
      // REFERENTIAL_CONSTRAINTS already carries the parent and the rule;
      // joining KEY_COLUMN_USAGE for them makes REFERENCED_TABLE_NAME
      // ambiguous between the two tables and the query errors rather than
      // asserting.
      const [rows] = await pool.query(
        `SELECT REFERENCED_TABLE_NAME AS parent, DELETE_RULE AS onDelete
           FROM information_schema.REFERENTIAL_CONSTRAINTS
          WHERE CONSTRAINT_SCHEMA = DATABASE()
            AND TABLE_NAME = 'exercise_ai_cues'`,
      );
      const rules = Object.fromEntries(rows.map((r) => [r.parent, r.onDelete]));
      assert.equal(rules.exercises, 'CASCADE');
      assert.equal(rules.injuries, 'CASCADE');
    });

  // The validator caps titles at 120 and details at 400 before anything is
  // stored. The columns have to agree, or MySQL truncates mid-sentence what
  // the validator was willing to accept.
  await t.test('the columns are as wide as the validator allows', async () => {
    const [cols] = await pool.query('SHOW COLUMNS FROM exercise_ai_cues');
    const byName = Object.fromEntries(cols.map((c) => [c.Field, c.Type]));
    assert.match(byName.title, /varchar\(120\)/i);
    assert.match(byName.detail, /varchar\(400\)/i);
  });
});
