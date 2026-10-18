'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { manilaDay } = require('../src/lib/manila-day');
const { dailyTarget } = require('../src/lib/nutrition-target');

const FS_FOOD = {
  externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5,
  fiberG: 5, sugarG: 40, sodiumMg: 15,
};
// A serving description FatSecret could plausibly send that is longer than
// foods.serving_desc (VARCHAR(255)); upsertFatsecretFood must cap it rather
// than let the INSERT throw ER_DATA_TOO_LONG.
const FS_LONG_FOOD = {
  externalId: 'fs-long', name: 'Long Serving Food', servingDesc: 'x'.repeat(300),
  kcal: 100, proteinG: 1, carbsG: 1, fatG: 1,
};

test('nutrition endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let fatsecretDown = false;
  let fatsecretGets = 0;
  const fatsecret = {
    async search() { return []; },
    async get(id) {
      fatsecretGets += 1;
      if (fatsecretDown) throw new Error('down');
      if (id === FS_FOOD.externalId) return { ...FS_FOOD };
      if (id === FS_LONG_FOOD.externalId) return { ...FS_LONG_FOOD };
      return null;
    },
  };
  const app = buildTestApp({ pool, fatsecret });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [adobo] = await pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g)
     VALUES ('Chicken adobo', 'filipino', '1 serving (150 g)', 320, 28, 4, 21, 2.5)`,
  );
  const ADOBO = adobo.insertId;

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `nu${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'N' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId: res.body.data.user.userId,
      auth,
      day: (date) => request(app).get('/api/v1/nutrition/day').query(date ? { date } : {}).set(auth),
      log: (body) => request(app).post('/api/v1/nutrition/entries').set(auth).send(body),
      del: (id) => request(app).delete(`/api/v1/nutrition/entries/${id}`).set(auth),
      edit: (id, body) => request(app).patch(`/api/v1/nutrition/entries/${id}`).set(auth).send(body),
      patch: (body) => request(app).patch('/api/v1/profile').set(auth).send(body),
    };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/nutrition/day').expect(401);
    await request(app).post('/api/v1/nutrition/entries').send({}).expect(401);
    await request(app).delete('/api/v1/nutrition/entries/1').expect(401);
    await request(app).patch('/api/v1/nutrition/entries/1').send({ mealType: 'lunch', servings: 1 }).expect(401);
  });

  await t.test('an empty day for a new account: no target, fields named', async () => {
    const u = await freshUser();
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.date, manilaDay());
    assert.equal(day.target, null);
    assert.deepEqual(day.targetMissing, ['sex', 'dateOfBirth', 'heightCm', 'weightKg', 'activityLevel']);
    assert.deepEqual(day.totals, { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0 });
    assert.deepEqual(day.meals, { breakfast: [], lunch: [], dinner: [], snack: [] });
  });

  await t.test('a complete profile gets the computed target', async () => {
    const u = await freshUser();
    const profile = {
      sex: 'female', dateOfBirth: '2001-03-02', heightCm: 165, weightKg: 60,
      activityLevel: 'light', mainGoal: 'lose_weight',
    };
    await u.patch(profile).expect(200);
    const { day } = (await u.day().expect(200)).body.data;
    assert.deepEqual(day.target, dailyTarget(profile, manilaDay()).target);
    assert.deepEqual(day.targetMissing, []);
  });

  await t.test('logs a catalogue food, multiplying by servings', async () => {
    const u = await freshUser();
    await pool.query('UPDATE foods SET sugar_g = 2.5, sodium_mg = 300 WHERE food_id = ?', [ADOBO]);
    const res = await u.log({ mealType: 'lunch', servings: 1.5, food: { source: 'local', id: ADOBO } }).expect(201);
    const { entry } = res.body.data;
    assert.deepEqual({ ...entry, id: undefined }, {
      id: undefined, mealType: 'lunch', name: 'Chicken adobo', servingDesc: '1 serving (150 g)',
      servings: 1.5, kcal: 480, proteinG: 42, carbsG: 6, fatG: 31.5, fiberG: 3.75,
      sugarG: 3.75, sodiumMg: 450,
      source: 'local', foodId: ADOBO, externalId: null,
    });
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.meals.lunch.length, 1);
    assert.deepEqual(day.totals, { kcal: 480, proteinG: 42, carbsG: 6, fatG: 31.5, fiberG: 3.8, sugarG: 3.8, sodiumMg: 450 });
  });

  await t.test('a food with unknown fiber, sugar and sodium logs them null, and totals are unaffected', async () => {
    const u = await freshUser();
    const [plain] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g)
       VALUES ('Plain rice', 'international', '1 cup', 200, 4, 44, 0.4)`,
    );
    const { entry } = (await u.log({
      mealType: 'lunch', servings: 1, food: { source: 'local', id: plain.insertId },
    }).expect(201)).body.data;
    assert.equal(entry.fiberG, null);
    assert.equal(entry.sugarG, null);
    assert.equal(entry.sodiumMg, null);
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.totals.fiberG, 0);
    assert.equal(day.totals.sugarG, 0);
    assert.equal(day.totals.sodiumMg, 0);
  });

  await t.test('logs a manual food with calories from 4-4-9', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({
      mealType: 'snack', servings: 1,
      food: {
        source: 'manual', name: '  Turon  ', servingDesc: '1 piece', proteinG: 2, carbsG: 34, fatG: 6,
        fiberG: 4, sugarG: 4, sodiumMg: 250,
      },
    }).expect(201)).body.data;
    assert.equal(entry.name, 'Turon');
    assert.equal(entry.kcal, 198); // 8 + 136 + 54, unaffected by fiber, sugar or sodium
    assert.equal(entry.source, 'manual');
    assert.equal(entry.foodId, null);
    assert.equal(entry.servingDesc, '1 piece');
    assert.equal(entry.fiberG, 4);
    assert.equal(entry.sugarG, 4);
    assert.equal(entry.sodiumMg, 250);

    const { entry: noFiber } = (await u.log({
      mealType: 'snack', servings: 1,
      food: { source: 'manual', name: 'Unlisted', proteinG: 2, carbsG: 34, fatG: 6 },
    }).expect(201)).body.data;
    assert.equal(noFiber.fiberG, null);
    assert.equal(noFiber.sugarG, null);
    assert.equal(noFiber.sodiumMg, null);
  });

  await t.test('a FatSecret food is fetched by id, copied once, then reused', async () => {
    const u = await freshUser();
    fatsecretGets = 0;
    const a = (await u.log({ mealType: 'snack', servings: 1, food: { source: 'fatsecret', externalId: 'fs-1' } }).expect(201)).body.data.entry;
    const b = (await u.log({ mealType: 'snack', servings: 2, food: { source: 'fatsecret', externalId: 'fs-1' } }).expect(201)).body.data.entry;
    assert.equal(fatsecretGets, 2, 'numbers come from FatSecret, never the app');
    assert.equal(a.foodId, b.foodId);
    assert.equal(a.source, 'fatsecret');
    assert.equal(a.externalId, 'fs-1');
    assert.equal(b.kcal, 500);
    assert.equal(a.fiberG, 5, "snapshots the fake's fiberG");
    assert.equal(b.fiberG, 10, 'scaled by servings like any other number');
    assert.equal(a.sugarG, 40, "snapshots the fake's sugarG");
    assert.equal(b.sugarG, 80, 'scaled by servings like any other number');
    assert.equal(a.sodiumMg, 15, "snapshots the fake's sodiumMg");
    assert.equal(b.sodiumMg, 30, 'scaled by servings like any other number');
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM food_sources WHERE external_id = 'fs-1'");
    assert.equal(Number(n), 1);
  });

  await t.test('a FatSecret serving description longer than 255 chars is stored, not a 500', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({
      mealType: 'snack', servings: 1, food: { source: 'fatsecret', externalId: 'fs-long' },
    }).expect(201)).body.data;
    assert.equal(entry.servingDesc.length, 255);
    assert.equal(entry.servingDesc, 'x'.repeat(255));
    assert.equal(entry.fiberG, null, 'FS_LONG_FOOD has no fiberG at all, not just a null one');
    assert.equal(entry.sugarG, null);
    assert.equal(entry.sodiumMg, null);
  });

  await t.test('FatSecret down -> 502, unknown FatSecret food -> 404', async () => {
    const u = await freshUser();
    fatsecretDown = true;
    const down = await u.log({ mealType: 'snack', servings: 1, food: { source: 'fatsecret', externalId: 'fs-1' } }).expect(502);
    assert.equal(down.body.error.code, 'FATSECRET_UNAVAILABLE');
    fatsecretDown = false;
    const missing = await u.log({ mealType: 'snack', servings: 1, food: { source: 'fatsecret', externalId: 'nope' } }).expect(404);
    assert.equal(missing.body.error.code, 'FOOD_NOT_FOUND');
    await u.log({ mealType: 'snack', servings: 1, food: { source: 'local', id: 999999 } }).expect(404);
  });

  await t.test('validation', async () => {
    const u = await freshUser();
    const ok = { mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } };
    const bad = async (body, field) => {
      const res = await u.log(body).expect(400);
      assert.ok(['INVALID_NUTRITION_FIELD', 'INVALID_DATE'].includes(res.body.error.code), JSON.stringify(res.body));
      if (field) assert.deepEqual(res.body.error.details, [{ field }]);
    };
    await bad({ ...ok, mealType: 'brunch' }, 'mealType');
    await bad({ ...ok, servings: 0 }, 'servings');
    await bad({ ...ok, servings: 1.25 }, 'servings');
    await bad({ ...ok, servings: 20.5 }, 'servings');
    await bad({ ...ok, food: { source: 'other' } }, 'food');
    await bad({ ...ok, food: { source: 'manual', name: '', proteinG: 1, carbsG: 0, fatG: 0 } }, 'name');
    await bad({ ...ok, food: { source: 'manual', name: 'x'.repeat(101), proteinG: 1, carbsG: 0, fatG: 0 } }, 'name');
    await bad({ ...ok, food: { source: 'manual', name: 'Water', proteinG: 0, carbsG: 0, fatG: 0 } }, 'food');
    await bad({ ...ok, food: { source: 'manual', name: 'X', proteinG: 501, carbsG: 0, fatG: 0 } }, 'proteinG');
    await bad({ ...ok, food: { source: 'manual', name: 'X', proteinG: 1, carbsG: 0, fatG: 0, fiberG: 501 } }, 'fiberG');
    await bad({ ...ok, food: { source: 'manual', name: 'X', proteinG: 1, carbsG: 0, fatG: 0, sugarG: 501 } }, 'sugarG');
    await bad({ ...ok, food: { source: 'manual', name: 'X', proteinG: 1, carbsG: 0, fatG: 0, sodiumMg: 20001 } }, 'sodiumMg');
    await bad({ ...ok, food: { source: 'manual', name: 'X', proteinG: 1, carbsG: 0, fatG: 0, sodiumMg: 'x' } }, 'sodiumMg');
    await bad({ ...ok, food: { source: 'manual', name: 'X', servingDesc: 'y'.repeat(61), proteinG: 1, carbsG: 0, fatG: 0 } }, 'servingDesc');
    await bad({ ...ok, date: '2999-01-01' });
    await bad({ ...ok, date: '2026-02-30' });
    await u.day('2999-01-01').expect(400);
    await u.day('yesterday').expect(400);
  });

  await t.test('sugar and sodium accept their top boundary, and sodium rounds to one decimal', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({
      mealType: 'snack', servings: 1,
      food: { source: 'manual', name: 'Boundary', proteinG: 1, carbsG: 0, fatG: 0, sugarG: 500, sodiumMg: 20000 },
    }).expect(201)).body.data;
    assert.equal(entry.sugarG, 500);
    assert.equal(entry.sodiumMg, 20000);

    const { entry: rounded } = (await u.log({
      mealType: 'snack', servings: 1,
      food: { source: 'manual', name: 'Fractional sodium', proteinG: 1, carbsG: 0, fatG: 0, sodiumMg: 123.456 },
    }).expect(201)).body.data;
    assert.equal(rounded.sodiumMg, 123.5);
  });

  await t.test('a month or day out of range is INVALID_DATE, not a 500', async () => {
    const u = await freshUser();
    for (const date of ['2026-13-01', '2026-00-10', '2026-01-32']) {
      assert.equal((await u.day(date).expect(400)).body.error.code, 'INVALID_DATE', date);
      const res = await u.log({ date, mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(400);
      assert.equal(res.body.error.code, 'INVALID_DATE', date);
    }
  });

  await t.test('a past date logs to that day, not today', async () => {
    const u = await freshUser();
    const yesterday = manilaDay(1);
    await u.log({ date: yesterday, mealType: 'dinner', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201);
    assert.equal((await u.day(yesterday).expect(200)).body.data.day.meals.dinner.length, 1);
    assert.equal((await u.day().expect(200)).body.data.day.meals.dinner.length, 0);
  });

  await t.test('delete removes only your own entry', async () => {
    const owner = await freshUser();
    const other = await freshUser();
    const { entry } = (await owner.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    const stolen = await other.del(entry.id).expect(404);
    assert.equal(stolen.body.error.code, 'ENTRY_NOT_FOUND');
    assert.deepEqual((await owner.del(entry.id).expect(200)).body, { data: { deleted: true } });
    await owner.del(entry.id).expect(404);
    await owner.del('abc').expect(404);
  });

  await t.test('an entry keeps the serving text it was logged with', async () => {
    const u = await freshUser();
    const [soup] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g)
       VALUES ('Sinigang', 'filipino', '1 bowl', 180, 15, 8, 9)`,
    );
    await u.log({ mealType: 'dinner', servings: 1, food: { source: 'local', id: soup.insertId } }).expect(201);
    const fs = (await u.log({
      mealType: 'dinner', servings: 1, food: { source: 'fatsecret', externalId: 'fs-1' },
    }).expect(201)).body.data.entry;
    // A seed re-run or a later FatSecret refresh rewrites the foods rows.
    await pool.query("UPDATE foods SET serving_desc = 'relabelled' WHERE food_id IN (?, ?)", [soup.insertId, fs.foodId]);
    const { day } = (await u.day().expect(200)).body.data;
    assert.deepEqual(day.meals.dinner.map((e) => e.servingDesc), ['1 bowl', '1 glass']);
  });

  // The numbers an entry stores, read straight from meal_logs.
  const storedNumbers = async (id) => {
    const [[r]] = await pool.query(
      `SELECT servings, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg
         FROM meal_logs WHERE meal_log_id = ?`, [id],
    );
    return r;
  };
  const numbersOf = (e) => ({
    kcal: e.kcal, proteinG: e.proteinG, carbsG: e.carbsG, fatG: e.fatG,
    fiberG: e.fiberG, sugarG: e.sugarG, sodiumMg: e.sodiumMg,
  });
  const MANUAL = {
    source: 'manual', name: 'Pandesal', servingDesc: '1 roll', proteinG: 10.25, carbsG: 3.33, fatG: 1.11,
    fiberG: 2, sugarG: 1, sodiumMg: 12.3,
  };

  await t.test('edit moves an entry to another meal, totals unchanged', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    const before = (await u.day().expect(200)).body.data.day.totals;
    const res = await u.edit(entry.id, { mealType: 'snack', servings: 1 }).expect(200);
    assert.deepEqual(res.body.data.entry, { ...entry, mealType: 'snack' });
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.meals.lunch.length, 0);
    assert.deepEqual(day.meals.snack.map((e) => e.id), [entry.id]);
    assert.deepEqual(day.totals, before);
  });

  await t.test('edit rescales by servings from the stored numbers, rounded like POST', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({ mealType: 'breakfast', servings: 1, food: MANUAL }).expect(201)).body.data;
    assert.equal(entry.kcal, 64); // 41 + 13.32 + 9.99

    const doubled = (await u.edit(entry.id, { mealType: 'breakfast', servings: 2 }).expect(200)).body.data.entry;
    assert.equal(doubled.servings, 2);
    assert.deepEqual(numbersOf(doubled), {
      kcal: 128, proteinG: 20.5, carbsG: 6.66, fatG: 2.22, fiberG: 4, sugarG: 2, sodiumMg: 24.6,
    });
    const halved = (await u.edit(entry.id, { mealType: 'breakfast', servings: 1 }).expect(200)).body.data.entry;
    assert.deepEqual(numbersOf(halved), numbersOf(entry));

    const rounded = (await u.edit(entry.id, { mealType: 'breakfast', servings: 1.5 }).expect(200)).body.data.entry;
    assert.deepEqual(numbersOf(rounded), {
      kcal: 96, proteinG: 15.38, carbsG: 5, fatG: 1.67, fiberG: 3, sugarG: 1.5, sodiumMg: 18.5,
    });
    const posted = (await u.log({ mealType: 'breakfast', servings: 1.5, food: MANUAL }).expect(201)).body.data.entry;
    assert.deepEqual(numbersOf(rounded), numbersOf(posted));
    assert.equal(rounded.name, 'Pandesal');
    assert.equal(rounded.servingDesc, '1 roll');
    assert.equal(rounded.source, 'manual');
  });

  await t.test('edit with the same servings leaves the stored numbers exactly as they were', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({ mealType: 'lunch', servings: 1, food: MANUAL }).expect(201)).body.data;
    // Unrounded, divide-then-multiply gives these back at the stored
    // precision. This guards against a change that rounds the per-serving
    // value first: 100 / 3 -> 33 -> 99, 7 / 3 -> 2.33 -> 6.99, 10 / 3 -> 3.3 -> 9.9.
    await pool.query(
      `UPDATE meal_logs SET servings = 3, calories = 100, protein_g = 7, carbs_g = 7, fat_g = 7,
                            fiber_g = 7, sugar_g = 7, sodium_mg = 10 WHERE meal_log_id = ?`, [entry.id],
    );
    const before = await storedNumbers(entry.id);
    const edited = (await u.edit(entry.id, { mealType: 'dinner', servings: 3 }).expect(200)).body.data.entry;
    assert.equal(edited.mealType, 'dinner');
    assert.deepEqual(await storedNumbers(entry.id), before);
    assert.deepEqual(numbersOf(edited), {
      kcal: 100, proteinG: 7, carbsG: 7, fatG: 7, fiberG: 7, sugarG: 7, sodiumMg: 10,
    });
  });

  await t.test("edit rescales a catalogue food from the entry, not the food's current row", async () => {
    const u = await freshUser();
    const [bibingka] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g)
       VALUES ('Bibingka', 'filipino', '1 piece', 200, 5, 30, 6)`,
    );
    const { entry } = (await u.log({
      mealType: 'breakfast', servings: 1, food: { source: 'local', id: bibingka.insertId },
    }).expect(201)).body.data;
    // A later correction to the food list must not rewrite what was logged.
    await pool.query(
      'UPDATE foods SET calories = 999, protein_g = 99, carbs_g = 99, fat_g = 99 WHERE food_id = ?', [bibingka.insertId],
    );
    const edited = (await u.edit(entry.id, { mealType: 'breakfast', servings: 2 }).expect(200)).body.data.entry;
    assert.deepEqual(numbersOf(edited), {
      kcal: 400, proteinG: 10, carbsG: 60, fatG: 12, fiberG: null, sugarG: null, sodiumMg: null,
    });
    assert.equal(edited.source, 'local');
    assert.equal(edited.foodId, bibingka.insertId);
    assert.equal(edited.servingDesc, '1 piece');
  });

  await t.test("edit with the user's own numbers makes the entry manual and leaves the food alone", async () => {
    const u = await freshUser();
    const [[foodBefore]] = await pool.query('SELECT * FROM foods WHERE food_id = ?', [ADOBO]);
    const { entry } = (await u.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    const edited = (await u.edit(entry.id, {
      mealType: 'dinner', servings: 1.5,
      food: {
        source: 'manual', name: '  Homemade adobo ', servingDesc: '1 cup',
        proteinG: 26, carbsG: 3, fatG: 12.3, fiberG: null, sugarG: 1, sodiumMg: 640,
      },
    }).expect(200)).body.data.entry;
    assert.deepEqual({ ...edited, id: undefined }, {
      id: undefined, mealType: 'dinner', name: 'Homemade adobo', servingDesc: '1 cup', servings: 1.5,
      kcal: 341, // round(104 + 12 + 110.7) = 227 per serving, x 1.5 = 340.5 -> 341
      proteinG: 39, carbsG: 4.5, fatG: 18.45, fiberG: null, sugarG: 1.5, sodiumMg: 960,
      source: 'manual', foodId: null, externalId: null,
    });
    const [[row]] = await pool.query('SELECT logged_via, food_id, custom_name FROM meal_logs WHERE meal_log_id = ?', [entry.id]);
    assert.deepEqual({ ...row }, { logged_via: 'manual', food_id: null, custom_name: 'Homemade adobo' });
    const [[foodAfter]] = await pool.query('SELECT * FROM foods WHERE food_id = ?', [ADOBO]);
    assert.deepEqual(foodAfter, foodBefore);
  });

  await t.test('edit keeps unknown fiber, sugar and sodium unknown on a rescale', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({
      mealType: 'snack', servings: 1, food: { source: 'manual', name: 'Unlisted', proteinG: 2, carbsG: 34, fatG: 6 },
    }).expect(201)).body.data;
    const edited = (await u.edit(entry.id, { mealType: 'snack', servings: 2.5 }).expect(200)).body.data.entry;
    assert.equal(edited.kcal, 495);
    assert.equal(edited.fiberG, null);
    assert.equal(edited.sugarG, null);
    assert.equal(edited.sodiumMg, null);
  });

  await t.test('edit only finds your own entry', async () => {
    const owner = await freshUser();
    const other = await freshUser();
    const { entry } = (await owner.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    const body = { mealType: 'snack', servings: 2 };
    for (const id of [entry.id + 100000, 'abc', 0, -1]) {
      const res = await owner.edit(id, body).expect(404);
      assert.deepEqual(res.body.error.code, 'ENTRY_NOT_FOUND', String(id));
      assert.equal(res.body.error.message, 'No such entry.');
    }
    assert.equal((await other.edit(entry.id, body).expect(404)).body.error.code, 'ENTRY_NOT_FOUND');
    const { day } = (await owner.day().expect(200)).body.data;
    assert.deepEqual(day.meals.lunch, [entry], 'untouched by the refused edits');
  });

  await t.test('edit of an entry deleted mid-save is a 404, never a 200 with no entry', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    // The same database, but the row goes -- as a delete from another
    // device would take it -- between the edit's read and its write.
    const racing = new Proxy(pool, {
      get(target, prop) {
        if (prop === 'query') {
          return async (sql, params) => {
            if (/^\s*UPDATE meal_logs SET/.test(sql)) {
              await target.query('DELETE FROM meal_logs WHERE meal_log_id = ?', [entry.id]);
            }
            return target.query(sql, params);
          };
        }
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      },
    });
    const res = await request(buildTestApp({ pool: racing, fatsecret }))
      .patch(`/api/v1/nutrition/entries/${entry.id}`).set(u.auth)
      .send({ mealType: 'snack', servings: 2 }).expect(404);
    assert.equal(res.body.error.code, 'ENTRY_NOT_FOUND');
    assert.equal(res.body.error.message, 'No such entry.');
  });

  await t.test('edit validation', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({ mealType: 'lunch', servings: 1, food: { source: 'local', id: ADOBO } }).expect(201)).body.data;
    const ok = { mealType: 'lunch', servings: 1 };
    const bad = async (body, field) => {
      const res = await u.edit(entry.id, body).expect(400);
      assert.equal(res.body.error.code, 'INVALID_NUTRITION_FIELD', JSON.stringify(res.body));
      assert.deepEqual(res.body.error.details, [{ field }]);
    };
    await bad({ ...ok, mealType: 'brunch' }, 'mealType');
    await bad({ servings: 1 }, 'mealType');
    await bad({ ...ok, servings: 0.25 }, 'servings');
    await bad({ ...ok, servings: 21 }, 'servings');
    await bad({ mealType: 'lunch' }, 'servings');
    await bad({ mealType: 'brunch', servings: 0.25 }, 'mealType');
    await bad({ ...ok, servings: 0.25, food: 'x' }, 'servings');
    await bad({ ...ok, food: { source: 'local', id: ADOBO } }, 'food');
    await bad({ ...ok, food: 'adobo' }, 'food');
    await bad({ ...ok, food: null }, 'food');
    await bad({ ...ok, food: { source: 'manual', name: 'Water', proteinG: 0, carbsG: 0, fatG: 0 } }, 'food');
    await bad({ ...ok, food: { source: 'manual', name: 'X' } }, 'proteinG');
    const { day } = (await u.day().expect(200)).body.data;
    assert.deepEqual(day.meals.lunch, [entry], 'untouched by the refused edits');
  });
});
