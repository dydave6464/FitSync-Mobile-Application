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

const PROFILE = {
  sex: 'female', dateOfBirth: '2001-03-02', heightCm: 165, weightKg: 60, activityLevel: 'light', mainGoal: 'lose_weight',
};

test('GET /nutrition/suggestions', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const food = async (name, kcal, proteinG, carbsG, fatG, serving, { meals = '', rice = false, hidden = false } = {}) => {
    const [r] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, suggest_meals,
                          suggest_with_rice, hidden_at)
       VALUES (?, 'filipino', ?, ?, ?, ?, ?, ?, ?, IF(?, NOW(), NULL))`,
      [name, serving, kcal, proteinG, carbsG, fatG, meals, rice, hidden],
    );
    return r.insertId;
  };
  const RICE = await food('White rice', 206, 3.4, 47.5, 0.3, '1 cup (160 g)');
  const TINOLA = await food('Tinolang manok', 260, 26, 10, 12, '1 bowl (350 g)', { meals: 'lunch,dinner', rice: true });
  const BANGUS = await food('Grilled bangus', 206, 35.1, 0, 7.2, '1 piece (150 g)', { meals: 'lunch,dinner', rice: true });
  const PINAKBET = await food('Pinakbet', 150, 6, 14, 8, '1 cup', { meals: 'lunch,dinner', rice: true });
  // Hidden: shown, it would lead the list (336 kcal and 32.6 g with rice).
  const TUNA = await food('Inihaw na tuna (grilled tuna steak)', 130, 29.2, 0, 0.6, '1 slice (100 g)', {
    meals: 'lunch,dinner', rice: true, hidden: true,
  });
  const EGG = await food('Hard-boiled egg', 78, 6.3, 0.6, 5.3, '1 large', { meals: 'snack' });
  const BANANA = await food('Lakatan banana', 89, 1.1, 22.8, 0.3, '1 piece (100 g)', { meals: 'snack' });

  let seq = 0;
  const freshUser = async ({ profile = null } = {}) => {
    seq += 1;
    const email = `sg${seq}@example.com`;
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'S' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    if (profile) await request(app).patch('/api/v1/profile').set(auth).send(profile).expect(200);
    return {
      userId: res.body.data.user.userId,
      ask: (query) => request(app).get(`/api/v1/nutrition/suggestions${query}`).set(auth),
      log: (body) => request(app).post('/api/v1/nutrition/entries').set(auth).send(body).expect(201),
    };
  };
  const ids = (data) => data.suggestions.map((s) => s.food.foodId);
  const setHidden = (id, hidden) => pool.query(
    'UPDATE foods SET hidden_at = IF(?, NOW(), NULL) WHERE food_id = ?', [hidden, id],
  );

  await t.test('requires sign-in', async () => {
    await request(app).get('/api/v1/nutrition/suggestions?meal=lunch').expect(401);
  });

  await t.test('a missing or unknown meal is 400 INVALID_MEAL', async () => {
    const u = await freshUser();
    for (const query of ['', '?meal=brunch', '?meal=lunch&meal=dinner']) {
      const res = await u.ask(query).expect(400);
      assert.equal(res.body.error.code, 'INVALID_MEAL', query);
      assert.deepEqual(res.body.error.details, [{ field: 'meal' }], query);
    }
  });

  await t.test('no target: today, the most protein for the calories first, with 1 cup rice', async () => {
    const u = await freshUser();
    const { data } = (await u.ask('?meal=lunch').expect(200)).body;
    assert.deepEqual([data.date, data.meal, data.state, data.share], [manilaDay(), 'lunch', 'no_target', null]);
    assert.deepEqual(ids(data), [BANGUS, TINOLA, PINAKBET]);
    assert.deepEqual(data.suggestions[0], {
      food: {
        foodId: BANGUS, name: 'Grilled bangus', servingDesc: '1 piece (150 g)', kcal: 206, proteinG: 35.1, carbsG: 0, fatG: 7.2,
      },
      rice: {
        foodId: RICE, name: 'White rice', servingDesc: '1 cup (160 g)', kcal: 206, proteinG: 3.4, carbsG: 47.5, fatG: 0.3,
      },
      total: { kcal: 412, proteinG: 38.5, carbsG: 47.5, fatG: 7.5 },
      highProtein: true,
    });
  });

  await t.test('a hidden food is never suggested; shown again, it is', async () => {
    const u = await freshUser();
    assert.ok(!ids((await u.ask('?meal=lunch').expect(200)).body.data).includes(TUNA));
    await setHidden(TUNA, false);
    assert.equal(ids((await u.ask('?meal=lunch').expect(200)).body.data)[0], TUNA);
    await setHidden(TUNA, true);
  });

  await t.test('a snack is never served with rice', async () => {
    const u = await freshUser();
    const { data } = (await u.ask('?meal=snack').expect(200)).body;
    assert.deepEqual(ids(data), [EGG, BANANA]);
    assert.ok(data.suggestions.every((s) => s.rice === null));
  });

  await t.test('with White rice hidden, or only a FatSecret copy of it, plates are the dish alone', async () => {
    const u = await freshUser();
    await setHidden(RICE, true);
    const [copy] = await pool.query(
      `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g)
       VALUES ('White rice', 'international', '1 cup', 205, 4.3, 44.5, 0.4)`,
    );
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'fs-rice')", [copy.insertId]);
    const { data } = (await u.ask('?meal=lunch').expect(200)).body;
    assert.ok(data.suggestions.length > 0);
    for (const s of data.suggestions) {
      assert.equal(s.rice, null);
      assert.equal(s.total.kcal, s.food.kcal);
    }
    await setHidden(RICE, false);
  });

  await t.test('with a target: what is left today, shared with the empty main meals to come', async () => {
    const u = await freshUser({ profile: PROFILE });
    const { target } = dailyTarget(PROFILE, manilaDay());
    const lunch = (await u.ask('?meal=lunch').expect(200)).body.data;
    assert.equal(lunch.state, 'fits');
    assert.deepEqual(lunch.share, {
      kcal: Math.round(target.kcal / 2), proteinG: Math.round((target.proteinG / 2) * 10) / 10,
    });
    assert.deepEqual([...ids(lunch)].sort((a, b) => a - b), [TINOLA, BANGUS, PINAKBET]);
    const dinner = (await u.ask('?meal=dinner').expect(200)).body.data;
    assert.deepEqual(dinner.share, { kcal: target.kcal, proteinG: target.proteinG });
  });

  await t.test('a dish logged today is skipped and counted; another day is not', async () => {
    const u = await freshUser({ profile: PROFILE });
    const { target } = dailyTarget(PROFILE, manilaDay());
    await u.log({ mealType: 'breakfast', servings: 1, food: { source: 'local', id: TINOLA } });
    await pool.query(
      `INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, protein_g, carbs_g, fat_g, logged_via, log_date)
       VALUES (?, ?, 'lunch', 1, 206, 35.1, 0, 7.2, 'search', ?)`,
      [u.userId, BANGUS, manilaDay(1)],
    );
    const { data } = (await u.ask('?meal=lunch&date=2026-01-01').expect(200)).body;
    assert.equal(data.date, manilaDay(), 'always today');
    assert.ok(!ids(data).includes(TINOLA), 'logged today');
    assert.ok(ids(data).includes(BANGUS), 'logged yesterday only');
    assert.deepEqual(data.share, {
      kcal: Math.round((target.kcal - 260) / 2),
      proteinG: Math.round(((target.proteinG - 26) / 2) * 10) / 10,
    });
  });

  await t.test("today's calories reached: light snacks whatever the meal, never with rice", async () => {
    const u = await freshUser({ profile: PROFILE });
    await u.log({
      mealType: 'lunch', servings: 1,
      food: { source: 'manual', name: 'Fiesta plate', kcal: 5000, proteinG: 0, carbsG: 0, fatG: 0 },
    });
    const { data } = (await u.ask('?meal=dinner').expect(200)).body;
    assert.deepEqual([data.state, data.share], ['reached', null]);
    assert.deepEqual(ids(data), [EGG, BANANA]);
    assert.ok(data.suggestions.every((s) => s.rice === null));
  });
});
