'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { seedFoods } = require('../src/db/seed-foods');

const FOOD_KEYS = [
  'carbsG', 'category', 'fatG', 'fiberG', 'foodType', 'hidden', 'id', 'kcal', 'name', 'proteinG', 'servingDesc',
  'sodiumMg', 'sugarG', 'suggestMeals', 'suggestWithRice',
];

test('admin foods endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth, adminId } = await createTestAdmin(pool);
  const get = (path) => request(app).get(`/api/v1/admin${path}`).set(auth);
  const post = (path, body) => request(app).post(`/api/v1/admin${path}`).set(auth).send(body);
  const patch = (path, body) => request(app).patch(`/api/v1/admin${path}`).set(auth).send(body);
  const list = async (query) => (await get(`/foods${query}`).expect(200)).body.data;

  const insert = async (name, { listOrder = null, type = 'home', hidden = false } = {}) => {
    const [r] = await pool.query(
      `INSERT INTO foods (name, category, food_type, list_order, serving_desc, calories, protein_g, carbs_g, fat_g,
                          fiber_g, sugar_g, sodium_mg, hidden_at)
       VALUES (?, 'filipino', ?, ?, '1 cup', 300, 20, 10, 15, 1.5, 2, 400, IF(?, NOW(), NULL))`,
      [name, type, listOrder, hidden],
    );
    return r.insertId;
  };
  // Inserted out of order: the list answers by list_order (untyped/unlisted
  // last), then name.
  const sinigang = await insert('Sinigang', { listOrder: 2 });
  const adobo = await insert('Chicken adobo', { listOrder: 1 });
  const turon = await insert('Turon', { type: 'snack_sweet' });
  const bibingka = await insert('Bibingka', { type: 'bread_kakanin' });
  const kwekkwek = await insert('Kwek-kwek', { listOrder: 3, type: 'street', hidden: true });
  const copy = await insert('Banana');
  await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-1')", [copy]);

  const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('t@example.com', 'x', 'T')");
  await pool.query(
    `INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, protein_g, carbs_g, fat_g, logged_via, log_date)
     VALUES (?, ?, 'lunch', 1, 300, 20, 10, 15, 'search', '2026-11-01')`,
    [u.insertId, adobo],
  );
  const foodRow = async (id) => {
    const [[row]] = await pool.query(
      'SELECT name, calories, protein_g, added_by, hidden_at FROM foods WHERE food_id = ?', [id],
    );
    return row;
  };

  await t.test('a trainee token is refused', async () => {
    const token = signToken(u.insertId, TEST_JWT);
    const res = await request(app).get('/api/v1/admin/foods?show=shown')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test("show=shown lists FitSync's own shown foods in the food list's order", async () => {
    const data = await list('?show=shown');
    assert.deepEqual(data.foods.map((f) => f.id), [adobo, sinigang, bibingka, turon]);
    assert.deepEqual(data.counts, { shown: 4, hidden: 1, suggested: 0 });
    assert.deepEqual([data.page, data.limit, data.total], [1, 30, 4]);
    assert.deepEqual(Object.keys(data.foods[0]).sort(), FOOD_KEYS);
    assert.deepEqual(data.foods[0], {
      id: adobo, name: 'Chicken adobo', category: 'filipino', foodType: 'home', servingDesc: '1 cup',
      kcal: 300, proteinG: 20, carbsG: 10, fatG: 15, fiberG: 1.5, sugarG: 2, sodiumMg: 400, hidden: false,
      suggestMeals: [], suggestWithRice: false,
    });
  });

  await t.test('show=hidden lists the hidden ones', async () => {
    const data = await list('?show=hidden');
    assert.deepEqual(data.foods.map((f) => [f.id, f.hidden]), [[kwekkwek, true]]);
    assert.deepEqual(data.counts, { shown: 4, hidden: 1, suggested: 0 });
    assert.equal(data.total, 1);
  });

  await t.test('q matches the name; page and limit pick a slice', async () => {
    const found = await list('?show=shown&q=ADOBO');
    assert.deepEqual(found.foods.map((f) => f.id), [adobo]);
    assert.equal(found.total, 1);
    assert.deepEqual(found.counts, { shown: 4, hidden: 1, suggested: 0 });
    const page = await list('?show=shown&page=2&limit=3');
    assert.deepEqual(page.foods.map((f) => f.id), [turon]);
    assert.deepEqual([page.page, page.limit, page.total], [2, 3, 4]);
  });

  await t.test('a missing or unknown show is 400 INVALID_ADMIN_FIELD', async () => {
    for (const query of ['', '?show=all', '?show=shown&show=hidden']) {
      const res = await get(`/foods${query}`).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', query);
      assert.deepEqual(res.body.error.details, [{ field: 'show' }], query);
    }
  });

  const NEW_FOOD = {
    name: '  Ginataang bilo-bilo  ', category: 'filipino', foodType: 'snack_sweet', servingDesc: '1 bowl (250 g)',
    proteinG: 4, carbsG: 50, fatG: 12, fiberG: 2, sugarG: 20, sodiumMg: 30,
  };

  await t.test('adding a food answers 201 with it, added by the admin; calories from the macros', async () => {
    const res = await post('/foods', NEW_FOOD).expect(201);
    const { food } = res.body.data;
    assert.deepEqual(Object.keys(food).sort(), FOOD_KEYS);
    assert.equal(typeof food.id, 'number');
    assert.deepEqual({ ...food, id: 0 }, {
      id: 0, name: 'Ginataang bilo-bilo', category: 'filipino', foodType: 'snack_sweet', servingDesc: '1 bowl (250 g)',
      kcal: Math.round(4 * 4 + 4 * 50 + 9 * 12), proteinG: 4, carbsG: 50, fatG: 12, fiberG: 2, sugarG: 20, sodiumMg: 30,
      hidden: false, suggestMeals: [], suggestWithRice: false,
    });
    assert.equal((await foodRow(food.id)).added_by, adminId);
    // An added food has no place in the food list: it comes after the
    // list's own foods, by name among the others without one.
    assert.deepEqual((await list('?show=shown')).foods.map((f) => f.id), [adobo, sinigang, bibingka, food.id, turon]);
  });

  await t.test("a label's typed calories are kept; optional values may be left out", async () => {
    const res = await post('/foods', {
      name: 'Red Horse beer', category: 'international', foodType: 'drink', servingDesc: '1 bottle (330 ml)',
      kcal: 158.4, proteinG: 1, carbsG: 9, fatG: 0,
    }).expect(201);
    const { food } = res.body.data;
    assert.equal(food.kcal, 158);
    assert.deepEqual([food.fiberG, food.sugarG, food.sodiumMg], [null, null, null]);
  });

  await t.test('a food with no protein, carbs, fat or calories is refused', async () => {
    const res = await post('/foods', {
      ...NEW_FOOD, name: 'Water', proteinG: 0, carbsG: 0, fatG: 0,
    }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_NUTRITION_FIELD');
    assert.deepEqual(res.body.error.details, [{ field: 'food' }]);
  });

  await t.test('each bad field is a 400 naming it', async () => {
    const cases = [
      [{ name: '   ' }, 'INVALID_ADMIN_FIELD', 'name'],
      [{ name: 'x'.repeat(101) }, 'INVALID_ADMIN_FIELD', 'name'],
      [{ name: 42 }, 'INVALID_ADMIN_FIELD', 'name'],
      [{ category: 'asian' }, 'INVALID_ADMIN_FIELD', 'category'],
      [{ category: undefined }, 'INVALID_ADMIN_FIELD', 'category'],
      [{ foodType: 'dessert' }, 'INVALID_ADMIN_FIELD', 'foodType'],
      [{ servingDesc: undefined }, 'INVALID_ADMIN_FIELD', 'servingDesc'],
      [{ servingDesc: '  ' }, 'INVALID_ADMIN_FIELD', 'servingDesc'],
      [{ servingDesc: 'x'.repeat(61) }, 'INVALID_ADMIN_FIELD', 'servingDesc'],
      [{ proteinG: undefined }, 'INVALID_NUTRITION_FIELD', 'proteinG'],
      [{ fatG: 501 }, 'INVALID_NUTRITION_FIELD', 'fatG'],
      [{ kcal: 5001 }, 'INVALID_NUTRITION_FIELD', 'kcal'],
      [{ sodiumMg: -1 }, 'INVALID_NUTRITION_FIELD', 'sodiumMg'],
    ];
    for (const [change, code, field] of cases) {
      const res = await post('/foods', { ...NEW_FOOD, name: 'Puto', ...change }).expect(400);
      assert.equal(res.body.error.code, code, JSON.stringify(change));
      assert.deepEqual(res.body.error.details, [{ field }], JSON.stringify(change));
    }
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM foods WHERE name = 'Puto'");
    assert.equal(Number(n), 0);
  });

  await t.test("a name another of FitSync's foods has, in any case, is 409 FOOD_NAME_TAKEN", async () => {
    for (const name of ['chicken ADOBO', 'Kwek-kwek']) {
      const res = await post('/foods', { ...NEW_FOOD, name }).expect(409);
      assert.equal(res.body.error.code, 'FOOD_NAME_TAKEN', name);
      assert.equal(res.body.error.message, 'A food with that name already exists.');
    }
  });

  await t.test("a FatSecret copy's name is free to use", async () => {
    const res = await post('/foods', { ...NEW_FOOD, name: 'Banana', foodType: 'fruit_veg' }).expect(201);
    assert.notEqual(res.body.data.food.id, copy);
  });

  await t.test('editing changes only the fields sent, and marks the food as the admin\'s', async () => {
    const res = await patch(`/foods/${sinigang}`, { servingDesc: '1 bowl', category: 'international' }).expect(200);
    assert.deepEqual(res.body.data.food, {
      id: sinigang, name: 'Sinigang', category: 'international', foodType: 'home', servingDesc: '1 bowl',
      kcal: 300, proteinG: 20, carbsG: 10, fatG: 15, fiberG: 1.5, sugarG: 2, sodiumMg: 400, hidden: false,
      suggestMeals: [], suggestWithRice: false,
    });
    assert.equal((await foodRow(sinigang)).added_by, adminId);
  });

  await t.test('editing protein, carbs or fat works calories out again unless they are typed', async () => {
    const fromMacros = (await patch(`/foods/${sinigang}`, { proteinG: 30 }).expect(200)).body.data.food;
    assert.equal(fromMacros.kcal, Math.round(4 * 30 + 4 * 10 + 9 * 15));
    const typed = (await patch(`/foods/${sinigang}`, { kcal: 410, fatG: 16 }).expect(200)).body.data.food;
    assert.deepEqual([typed.kcal, typed.fatG], [410, 16]);
    const cleared = (await patch(`/foods/${sinigang}`, { kcal: null }).expect(200)).body.data.food;
    assert.equal(cleared.kcal, Math.round(4 * 30 + 4 * 10 + 9 * 16));
    // Other fields leave the calories as they are.
    await patch(`/foods/${sinigang}`, { kcal: 420 }).expect(200);
    const other = (await patch(`/foods/${sinigang}`, { fiberG: null, name: 'Sinigang na baboy' }).expect(200)).body.data.food;
    assert.deepEqual([other.kcal, other.fiberG, other.name], [420, null, 'Sinigang na baboy']);
  });

  await t.test('editing a food leaves meals already logged as they were', async () => {
    await patch(`/foods/${adobo}`, { proteinG: 40, kcal: 999 }).expect(200);
    const [[entry]] = await pool.query('SELECT calories, protein_g FROM meal_logs WHERE food_id = ?', [adobo]);
    assert.deepEqual([entry.calories, Number(entry.protein_g)], [300, 20]);
  });

  await t.test('an edit with a bad field is a 400 and changes nothing', async () => {
    const before = await foodRow(turon);
    for (const [body, field] of [[{ name: '' }, 'name'], [{ foodType: 'x' }, 'foodType'], [{ servingDesc: null }, 'servingDesc']]) {
      const res = await patch(`/foods/${turon}`, body).expect(400);
      assert.deepEqual(res.body.error.details, [{ field }]);
    }
    assert.equal((await patch(`/foods/${turon}`, { carbsG: -1 }).expect(400)).body.error.code, 'INVALID_NUTRITION_FIELD');
    assert.deepEqual(await foodRow(turon), before);
  });

  await t.test("renaming onto another own food's name is 409; a food may keep its own", async () => {
    const res = await patch(`/foods/${turon}`, { name: 'BIBINGKA' }).expect(409);
    assert.equal(res.body.error.code, 'FOOD_NAME_TAKEN');
    const same = await patch(`/foods/${turon}`, { name: 'turon' }).expect(200);
    assert.equal(same.body.data.food.name, 'turon');
  });

  await t.test('a FatSecret copy or an unknown food is 404 FOOD_NOT_FOUND', async () => {
    for (const id of [copy, 999999, 'abc']) {
      const res = await patch(`/foods/${id}`, { servingDesc: '1 piece' }).expect(404);
      assert.equal(res.body.error.code, 'FOOD_NOT_FOUND', String(id));
      assert.equal(res.body.error.message, 'No such food.');
    }
    assert.equal((await foodRow(copy)).added_by, null);
  });

  await t.test('hide and show answer the food with hidden set; repeats are harmless', async () => {
    const hidden = (await post(`/foods/${bibingka}/hide`).expect(200)).body.data.food;
    assert.deepEqual(Object.keys(hidden).sort(), FOOD_KEYS);
    assert.equal(hidden.hidden, true);
    assert.notEqual((await foodRow(bibingka)).hidden_at, null);
    assert.equal((await post(`/foods/${bibingka}/hide`).expect(200)).body.data.food.hidden, true);
    assert.deepEqual((await list('?show=hidden')).foods.map((f) => f.id), [kwekkwek, bibingka]);

    assert.equal((await post(`/foods/${bibingka}/show`).expect(200)).body.data.food.hidden, false);
    assert.equal((await foodRow(bibingka)).hidden_at, null);
    assert.equal((await post(`/foods/${bibingka}/show`).expect(200)).body.data.food.hidden, false);
  });

  await t.test('hiding or showing a FatSecret copy or an unknown food is 404', async () => {
    for (const action of ['hide', 'show']) {
      for (const id of [copy, 999999, 'abc']) {
        const res = await post(`/foods/${id}/${action}`).expect(404);
        assert.equal(res.body.error.code, 'FOOD_NOT_FOUND', `${action} ${id}`);
      }
    }
    assert.equal((await foodRow(copy)).hidden_at, null);
  });

  let tortang;

  await t.test('a food is suggested for the meals chosen, in meal order, with rice only beside a main meal', async () => {
    const lunch = (await patch(`/foods/${adobo}`, { suggestMeals: ['dinner', 'lunch'], suggestWithRice: true })
      .expect(200)).body.data.food;
    assert.deepEqual([lunch.suggestMeals, lunch.suggestWithRice], [['lunch', 'dinner'], true]);
    const [[row]] = await pool.query(
      'SELECT suggest_meals, suggest_with_rice, added_by FROM foods WHERE food_id = ?', [adobo],
    );
    assert.deepEqual([row.suggest_meals, row.suggest_with_rice, row.added_by], ['lunch,dinner', 1, adminId]);

    const snack = (await patch(`/foods/${turon}`, { suggestMeals: ['snack'], suggestWithRice: true })
      .expect(200)).body.data.food;
    assert.deepEqual([snack.suggestMeals, snack.suggestWithRice], [['snack'], false]);
  });

  await t.test("other edits keep a food's suggestions", async () => {
    const food = (await patch(`/foods/${adobo}`, { servingDesc: '1 plate' }).expect(200)).body.data.food;
    assert.deepEqual([food.suggestMeals, food.suggestWithRice], [['lunch', 'dinner'], true]);
  });

  await t.test('a food can be suggested as it is added', async () => {
    const res = await post('/foods', {
      ...NEW_FOOD, name: 'Tortang talong', foodType: 'home', suggestMeals: ['breakfast'], suggestWithRice: true,
    }).expect(201);
    tortang = res.body.data.food.id;
    assert.deepEqual([res.body.data.food.suggestMeals, res.body.data.food.suggestWithRice], [['breakfast'], true]);
  });

  await t.test('a bad suggestion field is a 400 naming it, and changes nothing', async () => {
    for (const [body, field] of [
      [{ suggestMeals: 'lunch' }, 'suggestMeals'],
      [{ suggestMeals: ['brunch'] }, 'suggestMeals'],
      [{ suggestMeals: null }, 'suggestMeals'],
      [{ suggestWithRice: 'yes' }, 'suggestWithRice'],
      [{ suggestWithRice: null }, 'suggestWithRice'],
    ]) {
      const res = await patch(`/foods/${adobo}`, body).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', JSON.stringify(body));
      assert.deepEqual(res.body.error.details, [{ field }], JSON.stringify(body));
    }
    const [[row]] = await pool.query('SELECT suggest_meals, suggest_with_rice FROM foods WHERE food_id = ?', [adobo]);
    assert.deepEqual([row.suggest_meals, row.suggest_with_rice], ['lunch,dinner', 1]);
  });

  await t.test('show=suggested lists shown foods suggested for any meal, and counts them', async () => {
    // A hidden food stays off the list, suggested or not.
    await patch(`/foods/${kwekkwek}`, { suggestMeals: ['snack'] }).expect(200);
    const data = await list('?show=suggested');
    assert.deepEqual(data.foods.map((f) => f.id), [adobo, tortang, turon]);
    assert.equal(data.total, 3);
    assert.equal(data.counts.suggested, 3);
    assert.equal(data.counts.hidden, 1);
  });

  await t.test('hiding a suggested food takes it off the suggested list', async () => {
    await post(`/foods/${turon}/hide`).expect(200);
    const data = await list('?show=suggested');
    assert.deepEqual(data.foods.map((f) => f.id), [adobo, tortang]);
    assert.equal(data.counts.suggested, 2);
    await post(`/foods/${turon}/show`).expect(200);
  });
});

// Suggestions are the seed's only on insert: an admin's choice survives a
// re-seed (spec 2026-11-09, section 3).
test("a re-seed keeps an admin's suggestion choices", async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  await seedFoods(testDbConfig());
  const app = buildTestApp({ pool });
  const { auth } = await createTestAdmin(pool);
  const idOf = async (name) => (await pool.query('SELECT food_id FROM foods WHERE name = ?', [name]))[0][0].food_id;
  const tinola = await idOf('Tinolang manok');
  const egg = await idOf('Hard-boiled egg');
  await request(app).patch(`/api/v1/admin/foods/${tinola}`).set(auth).send({ suggestMeals: ['snack'] }).expect(200);
  await request(app).patch(`/api/v1/admin/foods/${egg}`).set(auth).send({ suggestMeals: [] }).expect(200);

  await seedFoods(testDbConfig());

  const [rows] = await pool.query(
    'SELECT food_id, suggest_meals, suggest_with_rice FROM foods WHERE food_id IN (?, ?)', [tinola, egg],
  );
  const got = Object.fromEntries(rows.map((r) => [r.food_id, [r.suggest_meals, r.suggest_with_rice]]));
  assert.deepEqual(got[tinola], ['snack', 0]);
  assert.deepEqual(got[egg], ['', 0]);
});
