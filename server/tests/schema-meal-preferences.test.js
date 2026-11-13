'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

const SET = "set('pork','beef','chicken','fish','shellfish','egg')";

test('meal preferences schema (050-052)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('foods gains contains and users gains avoid_foods, both empty by default', async () => {
    const col = async (table, name) => {
      const [[r]] = await pool.query(`SHOW COLUMNS FROM ${table} LIKE ?`, [name]);
      return [r.Type, r.Null, r.Default];
    };
    assert.deepEqual(await col('foods', 'contains'), [SET, 'NO', '']);
    assert.deepEqual(await col('users', 'avoid_foods'), [SET, 'NO', '']);
  });

  await t.test('hidden dishes go with their user and with their food', async () => {
    const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('h@example.com', 'x', 'H')");
    const [f1] = await pool.query("INSERT INTO foods (name, calories) VALUES ('Hide one', 100)");
    const [f2] = await pool.query("INSERT INTO foods (name, calories) VALUES ('Hide two', 100)");
    await pool.query('INSERT INTO user_hidden_suggestions (user_id, food_id) VALUES (?, ?), (?, ?)',
      [u.insertId, f1.insertId, u.insertId, f2.insertId]);
    const count = async () => Number((await pool.query('SELECT COUNT(*) AS n FROM user_hidden_suggestions'))[0][0].n);
    assert.equal(await count(), 2);
    await pool.query('DELETE FROM foods WHERE food_id = ?', [f1.insertId]);
    assert.equal(await count(), 1);
    await pool.query('DELETE FROM users WHERE user_id = ?', [u.insertId]);
    assert.equal(await count(), 0);
  });

  // A database that had its foods before 050: undo 050, add foods, apply it again.
  await t.test("tags FitSync's own, admin-untouched foods by exact name", async () => {
    await pool.query('ALTER TABLE foods DROP COLUMN contains');
    await pool.query("DELETE FROM schema_migrations WHERE version = '050_food_contains.sql'");
    const add = async (name, { admin = false, fatsecret = false } = {}) => {
      const [r] = await pool.query('INSERT INTO foods (name, calories) VALUES (?, 100)', [name]);
      if (admin) {
        const [a] = await pool.query("INSERT INTO admins (email, password_hash, full_name) VALUES (?, 'x', 'A')", [`${name}@a.test`]);
        await pool.query('UPDATE foods SET added_by = ? WHERE food_id = ?', [a.insertId, r.insertId]);
      }
      if (fatsecret) await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', ?)", [r.insertId, `fs-${r.insertId}`]);
      return r.insertId;
    };
    const chopsuey = await add('Chopsuey');
    const tapsilog = await add('Tapsilog');
    const bangus = await add('Grilled bangus');
    const mango = await add('Carabao mango, ripe');
    const lower = await add('chopsuey ');
    const edited = await add('Pinakbet', { admin: true });
    const copy = await add('Sinigang na baboy', { fatsecret: true });
    await migrate(testDbConfig());
    const tags = async (id) => (await pool.query('SELECT contains FROM foods WHERE food_id = ?', [id]))[0][0].contains;
    assert.equal(await tags(chopsuey), 'pork,shellfish,egg');
    assert.equal(await tags(tapsilog), 'beef,egg');
    assert.equal(await tags(bangus), 'fish');
    assert.equal(await tags(mango), '');
    assert.equal(await tags(lower), '', 'exact name only');
    assert.equal(await tags(edited), '', "an admin's food is the admin's");
    assert.equal(await tags(copy), '', 'never a FatSecret copy');
  });
});
