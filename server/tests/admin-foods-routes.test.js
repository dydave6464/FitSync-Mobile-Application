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
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const localDriver = require('../src/services/storage/local');
const { Writable } = require('node:stream');
const { createLogger } = require('../src/lib/logger');

const FOOD_KEYS = [
  'carbsG', 'category', 'contains', 'fatG', 'fiberG', 'foodType', 'hidden', 'id', 'kcal', 'name', 'photoUrl',
  'proteinG', 'servingDesc', 'sodiumMg', 'sugarG', 'suggestMeals', 'suggestWithRice',
];
// Tiny images built here, never files in git: the magic bytes and padding.
const JPEG = Buffer.from([0xff, 0xd8, 0xff, ...Array(64).fill(0)]);
const JPEG_2 = Buffer.from([0xff, 0xd8, 0xff, ...Array(64).fill(1)]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d]);
const b64 = (buf) => buf.toString('base64');
const PHOTO_URL = /^\/storage\/foods\/[0-9a-f-]{36}\.jpg$/;

test('admin foods endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  // A real disk driver in a temp folder, so tests can see files come and go.
  const storageDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fitsync-food-photos-'));
  const app = buildTestApp({ pool, storage: localDriver.create(storageDir) });
  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
    fs.rmSync(storageDir, { recursive: true, force: true });
  });

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
      suggestMeals: [], suggestWithRice: false, contains: [], photoUrl: null,
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
      hidden: false, suggestMeals: [], suggestWithRice: false, contains: [], photoUrl: null,
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
      suggestMeals: [], suggestWithRice: false, contains: [], photoUrl: null,
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

  let tagged;

  await t.test('a food can be tagged with what it contains as it is added, in the groups\' order', async () => {
    const res = await post('/foods', {
      ...NEW_FOOD, name: 'Tortang giniling', foodType: 'home', contains: ['egg', 'pork'],
    }).expect(201);
    tagged = res.body.data.food.id;
    assert.deepEqual(res.body.data.food.contains, ['pork', 'egg']);
    const [[row]] = await pool.query('SELECT contains FROM foods WHERE food_id = ?', [tagged]);
    assert.equal(row.contains, 'pork,egg');
  });

  await t.test('the food list carries contains', async () => {
    const data = await list('?show=shown&q=giniling');
    assert.deepEqual(data.foods.map((f) => [f.id, f.contains]), [[tagged, ['pork', 'egg']]]);
  });

  await t.test("other edits keep a food's contains; an empty list clears it", async () => {
    const kept = (await patch(`/foods/${tagged}`, { servingDesc: '1 slice' }).expect(200)).body.data.food;
    assert.deepEqual(kept.contains, ['pork', 'egg']);
    const cleared = (await patch(`/foods/${tagged}`, { contains: [] }).expect(200)).body.data.food;
    assert.deepEqual(cleared.contains, []);
    const [[row]] = await pool.query('SELECT contains FROM foods WHERE food_id = ?', [tagged]);
    assert.equal(row.contains, '');
  });

  await t.test('a bad contains is a 400 INVALID_ADMIN_FIELD naming it, and changes nothing', async () => {
    await patch(`/foods/${tagged}`, { contains: ['beef'] }).expect(200);
    for (const contains of [['peanuts'], 'pork', [1]]) {
      const res = await patch(`/foods/${tagged}`, { contains }).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', JSON.stringify(contains));
      assert.deepEqual(res.body.error.details, [{ field: 'contains' }], JSON.stringify(contains));
      const created = await post('/foods', { ...NEW_FOOD, name: 'Bad tags', contains }).expect(400);
      assert.deepEqual(created.body.error.details, [{ field: 'contains' }], JSON.stringify(contains));
    }
    const [[row]] = await pool.query('SELECT contains FROM foods WHERE food_id = ?', [tagged]);
    assert.equal(row.contains, 'beef');
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

  // Dish photos (round 3, spec 2026-11-13): the file lives in storage, the
  // row keeps its key, and answers carry only its URL.
  const keyOf = (url) => url.replace(/^\/storage\//, '');
  const fileOf = (url) => path.join(storageDir, keyOf(url));
  const photoKeyOf = async (id) => (await pool.query('SELECT photo_key FROM foods WHERE food_id = ?', [id]))[0][0]
    .photo_key;
  const filesIn = () => {
    const dir = path.join(storageDir, 'foods');
    return fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
  };
  let photoFood;
  let photoUrl;

  await t.test('a food added with a photo stores it and answers its URL', async () => {
    const res = await post('/foods', {
      ...NEW_FOOD, name: 'Puto with photo', image: b64(JPEG), mimeType: 'image/jpeg',
    }).expect(201);
    const { food } = res.body.data;
    assert.deepEqual(Object.keys(food).sort(), FOOD_KEYS);
    assert.match(food.photoUrl, PHOTO_URL);
    assert.deepEqual(fs.readFileSync(fileOf(food.photoUrl)), JPEG);
    assert.equal(await photoKeyOf(food.id), keyOf(food.photoUrl));
    photoFood = food.id;
    photoUrl = food.photoUrl;
  });

  await t.test('an edit with only a name keeps the photo', async () => {
    const { food } = (await patch(`/foods/${photoFood}`, { name: 'Puto (with photo)' }).expect(200)).body.data;
    assert.equal(food.photoUrl, photoUrl);
    assert.ok(fs.existsSync(fileOf(photoUrl)));
  });

  await t.test('the food list carries photoUrl and never photoKey', async () => {
    const data = await list('?show=shown&q=with%20photo');
    assert.deepEqual(data.foods.map((f) => [f.id, f.photoUrl]), [[photoFood, photoUrl]]);
    const all = await list('?show=shown');
    assert.ok(all.foods.every((f) => Object.hasOwn(f, 'photoUrl') && !Object.hasOwn(f, 'photoKey')));
  });

  await t.test('hide and show answer the photo URL too', async () => {
    assert.equal((await post(`/foods/${photoFood}/hide`).expect(200)).body.data.food.photoUrl, photoUrl);
    assert.equal((await post(`/foods/${photoFood}/show`).expect(200)).body.data.food.photoUrl, photoUrl);
  });

  await t.test('another photo replaces it: a new URL, the old file gone', async () => {
    const { food } = (await patch(`/foods/${photoFood}`, { image: b64(JPEG_2), mimeType: 'image/jpeg' })
      .expect(200)).body.data;
    assert.match(food.photoUrl, PHOTO_URL);
    assert.notEqual(food.photoUrl, photoUrl);
    assert.deepEqual(fs.readFileSync(fileOf(food.photoUrl)), JPEG_2);
    assert.equal(fs.existsSync(fileOf(photoUrl)), false);
    photoUrl = food.photoUrl;
  });

  await t.test('an old photo that will not delete is only logged: the replace still succeeds', async () => {
    // Same disk, but every delete fails; a capturing logger sees the warning.
    let logged = '';
    const destination = new Writable({ write(chunk, _enc, cb) { logged += chunk.toString(); cb(); } });
    const busyApp = buildTestApp({
      pool,
      storage: {
        ...localDriver.create(storageDir),
        delete: async () => { throw Object.assign(new Error('busy'), { code: 'EBUSY' }); },
      },
      logger: createLogger({ level: 'warn', env: 'production', destination }),
    });
    const res = await request(busyApp).patch(`/api/v1/admin/foods/${photoFood}`).set(auth)
      .send({ image: b64(JPEG), mimeType: 'image/jpeg' }).expect(200);
    const { food } = res.body.data;
    assert.match(food.photoUrl, PHOTO_URL);
    assert.notEqual(food.photoUrl, photoUrl);
    assert.equal(await photoKeyOf(photoFood), keyOf(food.photoUrl));
    assert.ok(fs.existsSync(fileOf(photoUrl)), 'the old file is still on disk');
    const warning = logged.split('\n').filter(Boolean).map((line) => JSON.parse(line))
      .find((entry) => entry.msg === 'old food photo not deleted');
    assert.ok(warning, 'the failed delete is logged');
    assert.equal(warning.code, 'EBUSY');
    // Tidy up through the real driver so later tests see one file per photo.
    fs.rmSync(fileOf(photoUrl));
    photoUrl = food.photoUrl;
  });

  await t.test('a photoKey a client sends is ignored', async () => {
    const { food } = (await patch(`/foods/${photoFood}`, { photoKey: 'foods/other.jpg' }).expect(200)).body.data;
    assert.equal(food.photoUrl, photoUrl);
    assert.equal(await photoKeyOf(photoFood), keyOf(photoUrl));
  });

  await t.test('removePhoto with a new image is a 400 naming removePhoto, and changes nothing', async () => {
    const before = filesIn();
    const res = await patch(`/foods/${photoFood}`, {
      removePhoto: true, image: b64(JPEG), mimeType: 'image/jpeg',
    }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD');
    assert.deepEqual(res.body.error.details, [{ field: 'removePhoto' }]);
    assert.equal(await photoKeyOf(photoFood), keyOf(photoUrl));
    assert.deepEqual(filesIn(), before);
  });

  await t.test('removePhoto anything but true is a 400 naming removePhoto', async () => {
    const res = await patch(`/foods/${photoFood}`, { removePhoto: 'yes' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD');
    assert.deepEqual(res.body.error.details, [{ field: 'removePhoto' }]);
    assert.equal(await photoKeyOf(photoFood), keyOf(photoUrl));
    assert.ok(fs.existsSync(fileOf(photoUrl)));
  });

  await t.test('a bad image is 400 INVALID_IMAGE: no file written, the food unchanged', async () => {
    const before = filesIn();
    for (const body of [
      { name: 'Renamed', image: b64(JPEG), mimeType: 'image/gif' },
      { name: 'Renamed', image: b64(JPEG), mimeType: 'image/png' },
      { name: 'Renamed', image: b64(PNG), mimeType: 'image/jpeg' },
    ]) {
      const res = await patch(`/foods/${photoFood}`, body).expect(400);
      assert.equal(res.body.error.code, 'INVALID_IMAGE', JSON.stringify(body.mimeType));
    }
    const added = await post('/foods', {
      ...NEW_FOOD, name: 'Bad photo food', image: b64(JPEG), mimeType: 'image/gif',
    }).expect(400);
    assert.equal(added.body.error.code, 'INVALID_IMAGE');
    assert.deepEqual(filesIn(), before);
    assert.equal((await foodRow(photoFood)).name, 'Puto (with photo)');
    assert.equal(await photoKeyOf(photoFood), keyOf(photoUrl));
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM foods WHERE name = 'Bad photo food'");
    assert.equal(n, 0);
  });

  await t.test('a food refused for its fields leaves no photo behind', async () => {
    const before = filesIn();
    const taken = await post('/foods', {
      ...NEW_FOOD, name: 'Puto (with photo)', image: b64(JPEG), mimeType: 'image/jpeg',
    }).expect(409);
    assert.equal(taken.body.error.code, 'FOOD_NAME_TAKEN');
    const bad = await patch(`/foods/${photoFood}`, { name: '', image: b64(JPEG), mimeType: 'image/jpeg' })
      .expect(400);
    assert.equal(bad.body.error.code, 'INVALID_ADMIN_FIELD');
    assert.deepEqual(bad.body.error.details, [{ field: 'name' }]);
    assert.deepEqual(filesIn(), before);
    assert.equal(await photoKeyOf(photoFood), keyOf(photoUrl));
  });

  await t.test('a photo for a FatSecret copy or an unknown food is 404, and nothing is stored', async () => {
    const before = filesIn();
    for (const id of [copy, 999999]) {
      const res = await patch(`/foods/${id}`, { image: b64(JPEG), mimeType: 'image/jpeg' }).expect(404);
      assert.equal(res.body.error.code, 'FOOD_NOT_FOUND');
    }
    assert.deepEqual(filesIn(), before);
  });

  await t.test('removePhoto clears it and deletes the file', async () => {
    const { food } = (await patch(`/foods/${photoFood}`, { removePhoto: true }).expect(200)).body.data;
    assert.equal(food.photoUrl, null);
    assert.equal(await photoKeyOf(photoFood), null);
    assert.equal(fs.existsSync(fileOf(photoUrl)), false);
    assert.deepEqual(filesIn(), []);
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
