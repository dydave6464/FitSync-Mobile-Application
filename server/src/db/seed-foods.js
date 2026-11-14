'use strict';
const { createPool } = require('./pool');
const FOODS = require('./seeds/foods.json');

// Only rows with no food_sources row are FitSync's own; a FatSecret copy can
// share a name ("Banana") and must never be overwritten by the seed.
//
// added_by is set once an admin added or edited the food (the admin
// dashboard): the seed then leaves it as it is, rename included. Such a row
// is still found here, so the list's version is not inserted beside it.
const FIND_OWN = `
  SELECT f.food_id, f.added_by FROM foods f
    LEFT JOIN food_sources s ON s.food_id = f.food_id
   WHERE s.food_id IS NULL AND f.name = ?
   LIMIT 1
`;

// An admin may also rename a seeded food. Editing never moves list_order, so
// the food still sits at its place in the list, under a name the list doesn't
// have: that row is this list food, and the seed must not add the old name
// back beside it. An admin's food that still has a list name is that list
// food, wherever it sits.
const FIND_RENAMED_BY_ADMIN = `
  SELECT f.food_id FROM foods f
    LEFT JOIN food_sources s ON s.food_id = f.food_id
   WHERE s.food_id IS NULL AND f.added_by IS NOT NULL AND f.list_order = ? AND f.name NOT IN (?)
   LIMIT 1
`;

// A seed food renamed in foods.json: the existing row is renamed rather than
// a second one inserted, so meals already logged keep pointing at it and
// show the new name.
const RENAMES = { 'Steamed white rice': 'White rice' };
const LIST_NAMES = FOODS.map((f) => f.name);

async function seedFoods(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    let inserted = 0;
    let updated = 0;
    let unchanged = 0;
    for (const [from, to] of Object.entries(RENAMES)) {
      const [[old]] = await pool.query(FIND_OWN, [from]);
      const [[taken]] = await pool.query(FIND_OWN, [to]);
      if (old && old.added_by === null && !taken) await pool.query('UPDATE foods SET name = ? WHERE food_id = ?', [to, old.food_id]);
    }
    for (const [i, f] of FOODS.entries()) {
      const values = [f.category, f.type, i + 1, f.servingDesc, f.kcal, f.proteinG, f.carbsG, f.fatG, f.fiberG, f.sugarG ?? null, f.sodiumMg ?? null];
      const [[own]] = await pool.query(FIND_OWN, [f.name]);
      if (!own) {
        const [[renamed]] = await pool.query(FIND_RENAMED_BY_ADMIN, [i + 1, LIST_NAMES]);
        if (renamed) {
          unchanged += 1;
          continue;
        }
        // Local meal suggestions and what a dish contains are written here,
        // on insert, and nowhere else: after that they are the admin's (the
        // Meals tab), and the UPDATE below never touches them, so a re-seed
        // never undoes a choice.
        await pool.query(
          `INSERT INTO foods (name, category, food_type, list_order, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
                              suggest_meals, suggest_with_rice, contains)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [f.name, ...values, (f.suggestMeals || []).join(','), Boolean(f.suggestWithRice), (f.contains || []).join(',')],
        );
        inserted += 1;
        continue;
      }
      if (own.added_by !== null) {
        unchanged += 1;
        continue;
      }
      const [res] = await pool.query(
        `UPDATE foods SET category = ?, food_type = ?, list_order = ?, serving_desc = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?, fiber_g = ?, sugar_g = ?, sodium_mg = ?
          WHERE food_id = ?`,
        [...values, own.food_id],
      );
      // changedRows, not affectedRows: mysql2's CLIENT_FOUND_ROWS makes
      // affectedRows 1 for a matched-but-identical row (see seed-injuries.js).
      if (res.changedRows > 0) updated += 1;
      else unchanged += 1;
    }
    return { inserted, updated, unchanged, total: FOODS.length };
  } finally {
    await pool.end();
  }
}

module.exports = { seedFoods, FOODS };
