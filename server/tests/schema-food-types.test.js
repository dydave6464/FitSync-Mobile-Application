'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { FOOD_TYPES } = require('../src/db/foods');

test('food type schema (038)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('food_type is a nullable enum of the nine types, in order', async () => {
    const [[col]] = await pool.query(
      "SELECT COLUMN_TYPE AS type, IS_NULLABLE AS nullable FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'foods' AND COLUMN_NAME = 'food_type'",
    );
    assert.equal(col.type, `enum(${FOOD_TYPES.map((k) => `'${k}'`).join(',')})`);
    assert.equal(col.nullable, 'YES');
  });

  await t.test('list_order is a nullable int', async () => {
    const [[col]] = await pool.query(
      "SELECT DATA_TYPE AS type, IS_NULLABLE AS nullable FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'foods' AND COLUMN_NAME = 'list_order'",
    );
    assert.deepEqual([col.type, col.nullable], ['int', 'YES']);
  });
});
