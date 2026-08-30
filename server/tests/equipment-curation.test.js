'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('equipment curation schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('equipment carries the four curation columns', async () => {
    const [rows] = await pool.query(
      `SELECT column_name AS name, column_default AS def, is_nullable AS nullable
         FROM information_schema.columns
        WHERE table_schema = ? AND table_name = 'equipment'`,
      [testDbConfig().database],
    );
    const byName = new Map(rows.map((r) => [r.name, r]));
    for (const col of [
      'display_name', 'display_order', 'is_user_selectable', 'parent_equipment_id',
    ]) {
      assert.ok(byName.has(col), `equipment.${col} must exist`);
    }
    assert.equal(byName.get('is_user_selectable').nullable, 'NO');
    assert.equal(Number(byName.get('is_user_selectable').def), 0);
  });

  await t.test('a row the catalogue seed inserts is not selectable', async () => {
    // The catalogue seed writes (name) only. The DEFAULT is what keeps a new
    // upstream tag out of onboarding without anyone noticing.
    await pool.query("INSERT INTO equipment (name) VALUES ('kettlebell')");
    const [[row]] = await pool.query(
      "SELECT is_user_selectable AS sel FROM equipment WHERE name = 'kettlebell'",
    );
    assert.equal(Number(row.sel), 0);
  });

  await t.test('parent_equipment_id must reference a real row', async () => {
    await assert.rejects(
      () => pool.query('UPDATE equipment SET parent_equipment_id = 999999'),
      /foreign key|ER_NO_REFERENCED_ROW/i,
    );
  });
});
