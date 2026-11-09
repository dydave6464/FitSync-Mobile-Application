'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

const FILE = '048_meal_suggestions.sql';

test('meal suggestions schema (048)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('foods gains suggest_meals and suggest_with_rice and loses is_suggested', async () => {
    const [rows] = await pool.query('SHOW COLUMNS FROM foods');
    const col = Object.fromEntries(rows.map((r) => [r.Field, [r.Type, r.Null, r.Default]]));
    assert.deepEqual(col.suggest_meals, ["set('breakfast','lunch','dinner','snack')", 'NO', '']);
    assert.deepEqual(col.suggest_with_rice, ['tinyint(1)', 'NO', '0']);
    assert.equal(col.is_suggested, undefined);
  });

  await t.test('a new food is never suggested', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, calories) VALUES ('Taho', 150)");
    const [[row]] = await pool.query(
      'SELECT suggest_meals, suggest_with_rice FROM foods WHERE food_id = ?', [f.insertId],
    );
    assert.deepEqual([row.suggest_meals, row.suggest_with_rice], ['', 0]);
  });

  // A database that had its foods before 048: undo 048, add foods, and
  // apply it again.
  await t.test("marks the starting list on FitSync's own foods, by exact name", async () => {
    await pool.query(
      `ALTER TABLE foods DROP COLUMN suggest_meals, DROP COLUMN suggest_with_rice,
                         ADD COLUMN is_suggested BOOLEAN NOT NULL DEFAULT FALSE`,
    );
    await pool.query('DELETE FROM schema_migrations WHERE version = ?', [FILE]);
    const [a] = await pool.query(
      "INSERT INTO admins (email, password_hash, full_name) VALUES ('meals@fitsync.test', 'x', 'M')",
    );
    const add = async (name, { addedBy = null, fatsecret = false } = {}) => {
      const [r] = await pool.query('INSERT INTO foods (name, calories, added_by) VALUES (?, 100, ?)', [name, addedBy]);
      if (fatsecret) {
        await pool.query(
          "INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', ?)",
          [r.insertId, `fs-${r.insertId}`],
        );
      }
      return r.insertId;
    };
    const tapsilog = await add('Tapsilog');
    const torta = await add('Tortang talong');
    const tinola = await add('Tinolang manok');
    const egg = await add('Hard-boiled egg');
    const kawali = await add('Lechon kawali');
    const lowercase = await add('chicken adobo');
    const adminsOwn = await add('Chicken afritada', { addedBy: a.insertId });
    const copy = await add('Pinakbet', { fatsecret: true });

    assert.deepEqual(await migrate(testDbConfig()), [FILE]);

    const [rows] = await pool.query('SELECT food_id, suggest_meals, suggest_with_rice FROM foods');
    const got = Object.fromEntries(rows.map((r) => [r.food_id, [r.suggest_meals, r.suggest_with_rice]]));
    assert.deepEqual(got[tapsilog], ['breakfast', 0]);
    assert.deepEqual(got[torta], ['breakfast', 1]);
    assert.deepEqual(got[tinola], ['lunch,dinner', 1]);
    assert.deepEqual(got[egg], ['snack', 0]);
    // Off the list, not its exact name, an admin's own, or a FatSecret copy.
    for (const id of [kawali, lowercase, adminsOwn, copy]) assert.deepEqual(got[id], ['', 0], String(id));
  });
});
