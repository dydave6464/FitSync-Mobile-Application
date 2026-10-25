'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { loadMenuFoods, createMenuCache } = require('../src/db/vision-menu');

test('the menu the AI chooses from', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('menu@b.com', 'x', 'M')");
  const own = async (name, order) => (await pool.query(
    "INSERT INTO foods (name, category, food_type, list_order, serving_desc, calories) VALUES (?, 'filipino', 'home', ?, '1 cup (160 g)', 100)",
    [name, order],
  ))[0].insertId;
  const copy = async (name, externalId, logs) => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES (?, 'international', 100)", [name]);
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', ?)", [f.insertId, externalId]);
    for (let i = 0; i < logs; i += 1) {
      await pool.query(
        "INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, logged_via, log_date) VALUES (?, ?, 'lunch', 1, 100, 'search', CURDATE())",
        [u.insertId, f.insertId],
      );
    }
    return f.insertId;
  };
  await own('Chicken adobo', 2);
  await own('White rice', 1);
  await copy('Mango Shake', 'fs-1', 2);
  await copy('Ube Latte', 'fs-2', 5);
  await copy('white rice', 'fs-3', 9); // FitSync has White rice: FitSync's wins
  await copy('Never logged', 'fs-4', 0);

  await t.test('FitSync\'s foods in list order, then FatSecret copies by how often they are logged', async () => {
    const menu = await loadMenuFoods(pool);
    assert.deepEqual(menu.map((f) => [f.name, f.externalId]), [
      ['White rice', null], ['Chicken adobo', null], ['Ube Latte', 'fs-2'], ['Mango Shake', 'fs-1'],
    ]);
    assert.equal(menu[0].servingDesc, '1 cup (160 g)');
  });

  await t.test('only the top FatSecret copies are taken', async () => {
    const menu = await loadMenuFoods(pool, { fatsecretLimit: 1 });
    assert.deepEqual(menu.map((f) => f.name), ['White rice', 'Chicken adobo']);
  });
});

test('the menu cache reloads only when stale, and loads once for callers arriving together', async () => {
  let loads = 0;
  let clock = 0;
  const cache = createMenuCache({ ttlMs: 1000, now: () => clock, load: async () => { loads += 1; return [`menu ${loads}`]; } });
  const [a, b] = await Promise.all([cache.get('pool'), cache.get('pool')]);
  assert.deepEqual([a, b, loads], [['menu 1'], ['menu 1'], 1]);
  clock = 999;
  assert.deepEqual(await cache.get('pool'), ['menu 1']);
  clock = 1000;
  assert.deepEqual(await cache.get('pool'), ['menu 2']);
});
