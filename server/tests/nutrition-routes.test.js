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

const FS_FOOD = { externalId: 'fs-1', name: 'Mango Shake', servingDesc: '1 glass', kcal: 250, proteinG: 4, carbsG: 50, fatG: 3.5 };

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
      return id === FS_FOOD.externalId ? { ...FS_FOOD } : null;
    },
  };
  const app = buildTestApp({ pool, fatsecret });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [adobo] = await pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g)
     VALUES ('Chicken adobo', 'filipino', '1 serving (150 g)', 320, 28, 4, 21)`,
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
      day: (date) => request(app).get('/api/v1/nutrition/day').query(date ? { date } : {}).set(auth),
      log: (body) => request(app).post('/api/v1/nutrition/entries').set(auth).send(body),
      del: (id) => request(app).delete(`/api/v1/nutrition/entries/${id}`).set(auth),
      patch: (body) => request(app).patch('/api/v1/profile').set(auth).send(body),
    };
  };

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/nutrition/day').expect(401);
    await request(app).post('/api/v1/nutrition/entries').send({}).expect(401);
    await request(app).delete('/api/v1/nutrition/entries/1').expect(401);
  });

  await t.test('an empty day for a new account: no target, fields named', async () => {
    const u = await freshUser();
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.date, manilaDay());
    assert.equal(day.target, null);
    assert.deepEqual(day.targetMissing, ['sex', 'dateOfBirth', 'heightCm', 'weightKg', 'activityLevel']);
    assert.deepEqual(day.totals, { kcal: 0, proteinG: 0, carbsG: 0, fatG: 0 });
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
    const res = await u.log({ mealType: 'lunch', servings: 1.5, food: { source: 'local', id: ADOBO } }).expect(201);
    const { entry } = res.body.data;
    assert.deepEqual({ ...entry, id: undefined }, {
      id: undefined, mealType: 'lunch', name: 'Chicken adobo', servingDesc: '1 serving (150 g)',
      servings: 1.5, kcal: 480, proteinG: 42, carbsG: 6, fatG: 31.5,
      source: 'local', foodId: ADOBO, externalId: null,
    });
    const { day } = (await u.day().expect(200)).body.data;
    assert.equal(day.meals.lunch.length, 1);
    assert.deepEqual(day.totals, { kcal: 480, proteinG: 42, carbsG: 6, fatG: 31.5 });
  });

  await t.test('logs a manual food with calories from 4-4-9', async () => {
    const u = await freshUser();
    const { entry } = (await u.log({
      mealType: 'snack', servings: 1,
      food: { source: 'manual', name: '  Turon  ', servingDesc: '1 piece', proteinG: 2, carbsG: 34, fatG: 6 },
    }).expect(201)).body.data;
    assert.equal(entry.name, 'Turon');
    assert.equal(entry.kcal, 198); // 8 + 136 + 54
    assert.equal(entry.source, 'manual');
    assert.equal(entry.foodId, null);
    assert.equal(entry.servingDesc, '1 piece');
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
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM food_sources WHERE external_id = 'fs-1'");
    assert.equal(Number(n), 1);
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
    await bad({ ...ok, food: { source: 'manual', name: 'X', servingDesc: 'y'.repeat(61), proteinG: 1, carbsG: 0, fatG: 0 } }, 'servingDesc');
    await bad({ ...ok, date: '2999-01-01' });
    await bad({ ...ok, date: '2026-02-30' });
    await u.day('2999-01-01').expect(400);
    await u.day('yesterday').expect(400);
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
});
