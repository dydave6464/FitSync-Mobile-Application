'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { upsertFatsecretFood } = require('../src/db/foods');

const ROUNDS = 5;
const AT_ONCE = 8;

const food = (externalId) => ({
  externalId, name: `Food ${externalId}`, servingDesc: '1 cup', kcal: 100, proteinG: 1, carbsG: 2, fatG: 3,
});

const count = async (pool, sql, args) => Number((await pool.query(sql, args))[0][0].n);

// Two users logging the same FatSecret food for the first time at the same
// moment must both get its one foods row -- not a deadlock (a 500) and not a
// second copy. Several rounds, because a race only fails some of the time.
test('upsertFatsecretFood: concurrent first-time copies', async (t) => {
  const pool = createPool({ ...testDbConfig(), connectionLimit: AT_ONCE * 2 });
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('the same food at once: every caller gets the same id, one copy', async () => {
    for (let round = 0; round < ROUNDS; round += 1) {
      const id = `same-${round}`;
      const ids = await Promise.all(Array.from({ length: AT_ONCE }, () => upsertFatsecretFood(pool, food(id))));
      assert.equal(new Set(ids).size, 1, `round ${round}: ${ids}`);
      assert.equal(await count(pool, 'SELECT COUNT(*) AS n FROM food_sources WHERE external_id = ?', [id]), 1);
      assert.equal(await count(pool, 'SELECT COUNT(*) AS n FROM foods WHERE name = ?', [`Food ${id}`]), 1,
        'no orphaned foods row from a losing insert');
    }
  });

  await t.test('different foods at once: all succeed, one copy each', async () => {
    for (let round = 0; round < ROUNDS; round += 1) {
      const ids = Array.from({ length: AT_ONCE }, (_, i) => `diff-${round}-${i}`);
      const foodIds = await Promise.all(ids.map((id) => upsertFatsecretFood(pool, food(id))));
      assert.equal(new Set(foodIds).size, AT_ONCE, `round ${round}: ${foodIds}`);
      for (const id of ids) {
        assert.equal(await count(pool, 'SELECT COUNT(*) AS n FROM food_sources WHERE external_id = ?', [id]), 1);
      }
    }
  });

  await t.test('a later copy refreshes the numbers on the same row', async () => {
    const first = await upsertFatsecretFood(pool, food('refresh'));
    const again = await upsertFatsecretFood(pool, { ...food('refresh'), kcal: 140, servingDesc: '1 bowl' });
    assert.equal(again, first);
    const [[row]] = await pool.query('SELECT calories, serving_desc FROM foods WHERE food_id = ?', [first]);
    assert.deepEqual({ ...row }, { calories: 140, serving_desc: '1 bowl' });
  });

  await t.test('sugar_g and sodium_mg are written on insert and updated on refresh', async () => {
    const first = await upsertFatsecretFood(pool, { ...food('sugar-sodium'), sugarG: 1.2, sodiumMg: 345.5 });
    const [[row1]] = await pool.query('SELECT sugar_g, sodium_mg FROM foods WHERE food_id = ?', [first]);
    assert.equal(Number(row1.sugar_g), 1.2);
    assert.equal(Number(row1.sodium_mg), 345.5);

    const again = await upsertFatsecretFood(pool, { ...food('sugar-sodium'), sugarG: 2.5, sodiumMg: 500 });
    assert.equal(again, first);
    const [[row2]] = await pool.query('SELECT sugar_g, sodium_mg FROM foods WHERE food_id = ?', [first]);
    assert.equal(Number(row2.sugar_g), 2.5);
    assert.equal(Number(row2.sodium_mg), 500);
  });
});
