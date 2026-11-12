'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedFoods, FOODS } = require('../src/db/seed-foods');
const { searchOwnFoods } = require('../src/db/foods');

test('the seed list is well formed', () => {
  assert.ok(FOODS.length >= 240, `expected about 240 foods, got ${FOODS.length}`);
  assert.equal(new Set(FOODS.map((f) => f.name)).size, FOODS.length, 'names must be unique');
  for (const f of FOODS) {
    assert.ok(['filipino', 'international'].includes(f.category), f.name);
    assert.ok(typeof f.source === 'string' && f.source.length > 0, `${f.name} needs a source`);
    for (const k of ['proteinG', 'carbsG', 'fatG']) assert.ok(f[k] >= 0 && f[k] < 1000, `${f.name} ${k}`);
    assert.ok(typeof f.fiberG === 'number' && f.fiberG >= 0 && f.fiberG < 100, `${f.name} fiberG`);
    if (f.alcoholG !== undefined) assert.ok(typeof f.alcoholG === 'number' && f.alcoholG > 0 && f.alcoholG < 100, `${f.name} alcoholG`);
    assert.ok(typeof f.sugarG === 'number' && f.sugarG >= 0 && f.sugarG <= f.carbsG, `${f.name} sugarG`);
    assert.ok(typeof f.sodiumMg === 'number' && f.sodiumMg >= 0 && f.sodiumMg <= 10000, `${f.name} sodiumMg`);
    assert.ok(f.fiberG <= f.carbsG, `${f.name}: fiber is part of carbs`);
    // Atwater check, to catch a typo: within 40 kcal or 20 %. Alcohol is 7 kcal/g.
    const atwater = 4 * f.proteinG + 4 * f.carbsG + 9 * f.fatG + 7 * (f.alcoholG ?? 0);
    assert.ok(Math.abs(atwater - f.kcal) <= Math.max(40, f.kcal * 0.2), `${f.name}: ${f.kcal} vs ${atwater}`);
  }
  const { FOOD_TYPES } = require('../src/db/foods');
  for (const f of FOODS) assert.ok(FOOD_TYPES.includes(f.type), `${f.name} needs a valid type, got ${f.type}`);
  assert.equal(FOODS[0].name, 'White rice');
  assert.ok(!FOODS.some((f) => f.name === 'Steamed white rice'), 'renamed to White rice');
});

// View Local Filipino Meal Suggestions (spec 2026-11-09): the starting list
// of 35 dishes, by meal, and whether each comes with 1 cup of rice.
const LUNCH_DINNER = [
  'Tinolang manok', 'Sinigang na bangus (milkfish sour soup)', 'Sinigang na hipon', 'Sinigang na baboy',
  'Nilagang baka', 'Grilled bangus', 'Tilapia, grilled or steamed', 'Inihaw na tuna (grilled tuna steak)',
  'Paksiw na bangus (milkfish in vinegar)', 'Sarciadong isda (fish with tomato-egg sauce)',
  'Sutukil sinugba (grilled fish)', 'Ginataang tulingan (frigate tuna in coconut milk)', 'Chicken adobo',
  'Chicken afritada', 'Bistek tagalog', 'Lechon manok', 'Chicken inasal', 'Ginisang monggo', 'Pinakbet', 'Chopsuey',
  'Ginisang ampalaya with egg', 'Adobong kangkong',
];
const SNACKS = [
  'Saba banana, boiled', 'Kamote (sweet potato), boiled', 'Lakatan banana', 'Carabao mango, ripe',
  'Papaya fresh fruit', 'Pinya (pineapple)', 'Bayabas (guava)', 'Hard-boiled egg',
];

test('the starting list of local meal suggestions', () => {
  const MEALS = ['breakfast', 'lunch', 'dinner', 'snack'];
  assert.ok(
    FOODS.every((f) => (f.suggestMeals === undefined) === (f.suggestWithRice === undefined)),
    'both fields or neither',
  );
  const suggested = FOODS.filter((f) => f.suggestMeals !== undefined);
  for (const f of suggested) {
    assert.ok(Array.isArray(f.suggestMeals) && f.suggestMeals.length > 0, `${f.name} suggestMeals`);
    assert.ok(f.suggestMeals.every((m) => MEALS.includes(m)), `${f.name} suggestMeals`);
    assert.equal(typeof f.suggestWithRice, 'boolean', `${f.name} suggestWithRice`);
  }
  const group = (meals, rice) => suggested
    .filter((f) => f.suggestMeals.join(',') === meals && f.suggestWithRice === rice)
    .map((f) => f.name)
    .sort();
  assert.deepEqual(group('breakfast', false), ['Bangsilog', 'Tapsilog']);
  assert.deepEqual(group('breakfast', true), [
    'Daing na bangus', 'Tinapang galunggong (smoked round scad)', 'Tortang talong',
  ]);
  assert.deepEqual(group('lunch,dinner', true), [...LUNCH_DINNER].sort());
  assert.deepEqual(group('snack', false), [...SNACKS].sort());
  assert.equal(suggested.length, 35);
});

test('food seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('inserts every food', async () => {
    const s = await seedFoods(testDbConfig());
    assert.equal(s.inserted, FOODS.length);
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM foods');
    assert.equal(Number(n), FOODS.length);
  });

  await t.test('inserts the starting suggestions with each food', async () => {
    const [rows] = await pool.query(
      `SELECT name, suggest_meals, suggest_with_rice FROM foods
        WHERE name IN ('Tapsilog', 'Tortang talong', 'Tinolang manok', 'Hard-boiled egg', 'White rice', 'Lechon kawali')
        ORDER BY name`,
    );
    assert.deepEqual(rows.map((r) => [r.name, r.suggest_meals, r.suggest_with_rice]), [
      ['Hard-boiled egg', 'snack', 0],
      ['Lechon kawali', '', 0],
      ['Tapsilog', 'breakfast', 0],
      ['Tinolang manok', 'lunch,dinner', 1],
      ['Tortang talong', 'breakfast', 1],
      ['White rice', '', 0],
    ]);
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM foods WHERE suggest_meals <> ''");
    assert.equal(Number(n), 35);
  });

  await t.test('writes each food\'s type and its 1-based place in the list', async () => {
    const [[rice]] = await pool.query("SELECT food_type, list_order FROM foods WHERE name = 'White rice'");
    assert.deepEqual([rice.food_type, rice.list_order], ['home', 1]);
    const [[yum]] = await pool.query("SELECT food_type FROM foods WHERE name = 'Jollibee Yumburger'");
    assert.equal(yum.food_type, 'fast_food');
    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM foods WHERE food_type IS NULL OR list_order IS NULL');
    assert.equal(Number(n), 0);
  });

  // Read from the list rather than written here: the numbers are corrected as
  // they are verified, and this checks that fiber is seeded, not its value.
  await t.test('seeds Ginisang monggo\'s fiber_g from the list', async () => {
    const [[row]] = await pool.query("SELECT fiber_g FROM foods WHERE name = 'Ginisang monggo'");
    assert.equal(Number(row.fiber_g), FOODS.find((f) => f.name === 'Ginisang monggo').fiberG);
  });

  await t.test('seeds Nescafé Original\'s sugar and sodium from its label', async () => {
    const [[row]] = await pool.query("SELECT sugar_g, sodium_mg FROM foods WHERE name = 'Nescafé Original 3-in-1 coffee'");
    assert.deepEqual([Number(row.sugar_g), Number(row.sodium_mg)], [9.7, 124]);
  });

  // A beer's calories are mostly alcohol (7 kcal/g), which only the seed
  // file's alcoholG accounts for; the database keeps the drink's real kcal.
  await t.test('seeds a beer with its alcohol calories included', async () => {
    const [[row]] = await pool.query("SELECT calories FROM foods WHERE name = 'San Miguel Pale Pilsen'");
    assert.equal(row.calories, 129);
  });

  // The current PH label (2025): the sachet shrank from 28 g to 20 g, so the
  // weight belongs in the serving text.
  await t.test('seeds Nescafé Original as one 20 g sachet, as its label prints', async () => {
    const [[row]] = await pool.query(
      "SELECT serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g FROM foods WHERE name = 'Nescafé Original 3-in-1 coffee'",
    );
    assert.ok(row, 'Nescafé Original 3-in-1 coffee is seeded');
    assert.deepEqual(
      [row.serving_desc, row.calories, Number(row.protein_g), Number(row.carbs_g), Number(row.fat_g), Number(row.fiber_g)],
      ['1 sachet (20 g)', 88, 0.27, 14, 3.4, 0.34],
    );
  });

  // People type "nescafe" without the accent; the collation must match "é".
  await t.test('a search without the accent finds the Nescafé packs', async () => {
    const names = (await searchOwnFoods(pool, 'nescafe')).map((f) => f.name);
    assert.deepEqual(names.sort(), [
      'Nescafé Creamy White coffee', 'Nescafé Original 3-in-1 coffee', 'Nescafé Sugarfree Original coffee',
    ]);
  });

  await t.test('searching "coffee" finds every coffee pack', async () => {
    const names = (await searchOwnFoods(pool, 'coffee')).map((f) => f.name);
    assert.deepEqual(names.sort(), [
      '3-in-1 coffee', 'Black coffee', 'Great Taste White coffee', 'Kopiko Blanca coffee', 'Kopiko Brown coffee',
      'Nescafé Creamy White coffee', 'Nescafé Original 3-in-1 coffee', 'Nescafé Sugarfree Original coffee',
      'San Mig Sugar Free Original coffee', 'UCC 3-in-1 Regular coffee',
    ]);
  });

  await t.test('searching "bread" finds the loaf slices and named breads', async () => {
    const names = (await searchOwnFoods(pool, 'bread')).map((f) => f.name);
    assert.deepEqual(names.sort(), [
      'Cheese bread', 'Gardenia Classic White bread', 'Gardenia High Fiber Whole Wheat bread', 'Pinoy Tasty bread',
      'Spanish bread', 'Whole wheat bread',
    ]);
  });

  await t.test('is idempotent and reports nothing changed', async () => {
    const s = await seedFoods(testDbConfig());
    assert.deepEqual(s, { inserted: 0, updated: 0, unchanged: FOODS.length, total: FOODS.length });
  });

  // Suggestions are written once, on insert: after that they are the
  // admin's, and a re-seed must never put the list's back.
  await t.test('a re-seed leaves suggestions as they are now', async () => {
    await pool.query("UPDATE foods SET suggest_meals = 'snack', suggest_with_rice = FALSE WHERE name = 'Tinolang manok'");
    await pool.query("UPDATE foods SET suggest_meals = 'lunch' WHERE name = 'Lechon kawali'");
    const s = await seedFoods(testDbConfig());
    assert.deepEqual([s.inserted, s.updated], [0, 0]);
    const [rows] = await pool.query(
      "SELECT name, suggest_meals, suggest_with_rice FROM foods WHERE name IN ('Tinolang manok', 'Lechon kawali') ORDER BY name",
    );
    assert.deepEqual(rows.map((r) => [r.name, r.suggest_meals, r.suggest_with_rice]), [
      ['Lechon kawali', 'lunch', 0],
      ['Tinolang manok', 'snack', 0],
    ]);
  });

  await t.test('updates a changed number in place', async () => {
    await pool.query("UPDATE foods SET calories = 1 WHERE name = 'Chicken adobo'");
    const s = await seedFoods(testDbConfig());
    assert.equal(s.updated, 1);
    const [[row]] = await pool.query("SELECT calories FROM foods WHERE name = 'Chicken adobo'");
    assert.equal(row.calories, FOODS.find((f) => f.name === 'Chicken adobo').kcal);
  });

  // An admin added or edited it (added_by set): the seed must not undo that,
  // and must not insert the list's version beside it either.
  await t.test("leaves an admin's food as it is and inserts no duplicate", async () => {
    const [a] = await pool.query(
      "INSERT INTO admins (email, password_hash, full_name) VALUES ('seed-admin@fitsync.test', 'x', 'A')",
    );
    await pool.query(
      "UPDATE foods SET calories = 1, serving_desc = 'admin cup', added_by = ? WHERE name = 'Chicken adobo'",
      [a.insertId],
    );
    const s = await seedFoods(testDbConfig());
    assert.equal(s.inserted, 0);
    assert.equal(s.updated, 0);
    const [rows] = await pool.query("SELECT calories, serving_desc FROM foods WHERE name = 'Chicken adobo'");
    assert.deepEqual(rows.map((r) => [r.calories, r.serving_desc]), [[1, 'admin cup']]);
  });

  // The admin renamed a seeded food (PATCH keeps its list_order): the list's
  // name finds nothing, but the food is still there under the admin's name,
  // so the seed must not bring the old name back beside it.
  await t.test("does not re-add a seeded food an admin renamed", async () => {
    const [[admin]] = await pool.query("SELECT admin_id FROM admins WHERE email = 'seed-admin@fitsync.test'");
    await pool.query(
      "UPDATE foods SET name = 'Monggo guisado', added_by = ? WHERE name = 'Ginisang monggo'",
      [admin.admin_id],
    );
    const s = await seedFoods(testDbConfig());
    assert.equal(s.inserted, 0);
    const [rows] = await pool.query("SELECT name FROM foods WHERE name IN ('Ginisang monggo', 'Monggo guisado')");
    assert.deepEqual(rows.map((r) => r.name), ['Monggo guisado']);
  });

  // An admin's food that still has a list name is that list food, not a
  // renamed one, even when it sits at another food's place in the list.
  await t.test('still adds a missing list food when an admin food that kept its list name holds its place', async () => {
    const [[admin]] = await pool.query("SELECT admin_id FROM admins WHERE email = 'seed-admin@fitsync.test'");
    const tinola = FOODS.findIndex((f) => f.name === 'Tinolang manok') + 1;
    await pool.query("DELETE FROM foods WHERE name = 'Tinolang manok'");
    await pool.query("UPDATE foods SET list_order = ?, added_by = ? WHERE name = 'Bulalo'", [tinola, admin.admin_id]);
    const s = await seedFoods(testDbConfig());
    assert.equal(s.inserted, 1);
    const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM foods WHERE name = 'Tinolang manok'");
    assert.equal(Number(n), 1);
  });

  await t.test('never touches a FatSecret copy with the same name', async () => {
    const [f] = await pool.query("INSERT INTO foods (name, category, calories) VALUES ('Banana', 'international', 999)");
    await pool.query("INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', 'x1')", [f.insertId]);
    await seedFoods(testDbConfig());
    const [[copy]] = await pool.query('SELECT calories FROM foods WHERE food_id = ?', [f.insertId]);
    assert.equal(copy.calories, 999);
  });
});

test('food seed renames Steamed white rice in place', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const [r] = await pool.query(
    "INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g) VALUES ('Steamed white rice', 'filipino', '1 cup (160 g)', 205, 4.3, 44.5, 0.4)",
  );
  await seedFoods(testDbConfig());
  const [rows] = await pool.query("SELECT food_id, name FROM foods WHERE name IN ('White rice', 'Steamed white rice')");
  assert.deepEqual(rows.map((x) => [x.food_id, x.name]), [[r.insertId, 'White rice']]);
  const again = await seedFoods(testDbConfig());
  assert.equal(again.inserted, 0);
  assert.equal(again.updated, 0);
});

test("food seed never renames an admin's food", async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const [a] = await pool.query(
    "INSERT INTO admins (email, password_hash, full_name) VALUES ('seed-admin@fitsync.test', 'x', 'A')",
  );
  const [r] = await pool.query(
    `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, added_by)
     VALUES ('Steamed white rice', 'filipino', '1 cup (160 g)', 205, 4.3, 44.5, 0.4, ?)`,
    [a.insertId],
  );
  await seedFoods(testDbConfig());
  const [[kept]] = await pool.query('SELECT name, calories FROM foods WHERE food_id = ?', [r.insertId]);
  assert.deepEqual([kept.name, kept.calories], ['Steamed white rice', 205]);
  // The list's own White rice is added beside it.
  const [[{ n }]] = await pool.query("SELECT COUNT(*) AS n FROM foods WHERE name = 'White rice'");
  assert.equal(Number(n), 1);
});

// Snap a meal's menu: 72 researched foods appended after the original 244,
// every one with the grams of a serving in its text (the AI's grams are
// turned into servings with them).
test('the Snap a meal foods are in the list, each with its serving grams', () => {
  const added = FOODS.slice(244, 316);
  assert.equal(added[0].name, 'Beef caldereta');
  assert.equal(added.at(-1).name, 'Chico (sapodilla)');
  for (const f of added) {
    assert.match(f.servingDesc, /\(\s*~?\s*\d+(?:\.\d+)?\s*(g|ml)\s*\)/i, `${f.name} needs grams in its serving`);
    assert.ok(!('_agent' in f) && !('whyCommon' in f) && !('whyCommonSource' in f), `${f.name} carries research-only keys`);
  }
  const names = FOODS.map((f) => f.name);
  for (const n of ['Atchara (pickled green papaya)', 'Squid balls with sweet sauce (street food)', 'Dinuguan (pork blood stew)']) {
    assert.ok(names.includes(n), n);
  }
});

test('Fishball\'s sodium is FNRI\'s measured value plus the sauce', () => {
  const f = FOODS.find((x) => x.name === 'Fishball with sweet sauce (street food)');
  assert.equal(f.sodiumMg, 1873);
  assert.match(f.source, /G162/);
});

// The dish classifier's palabok had only a brand to point to (spec
// 2026-11-05-food-classifier, section 1).
test('a plain Pancit palabok follows the Snap a meal foods, with its serving grams', () => {
  assert.equal(FOODS.length, 317);
  const palabok = FOODS[316];
  assert.equal(palabok.name, 'Pancit palabok');
  assert.equal(palabok.category, 'filipino');
  assert.equal(palabok.type, 'home');
  assert.match(palabok.servingDesc, /\(\s*~?\s*\d+(?:\.\d+)?\s*(g|ml)\s*\)/i);
  for (const k of ['kcal', 'proteinG', 'carbsG', 'fatG', 'fiberG', 'sugarG', 'sodiumMg']) {
    assert.equal(typeof palabok[k], 'number', `${k} is a number`);
  }
  assert.ok(palabok.source.length > 20);
});
