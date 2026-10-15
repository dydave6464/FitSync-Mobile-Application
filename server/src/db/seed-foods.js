'use strict';
const { createPool } = require('./pool');
const FOODS = require('./seeds/foods.json');

// Only rows with no food_sources row are FitSync's own; a FatSecret copy can
// share a name ("Banana") and must never be overwritten by the seed.
const FIND_OWN = `
  SELECT f.food_id FROM foods f
    LEFT JOIN food_sources s ON s.food_id = f.food_id
   WHERE s.food_id IS NULL AND f.name = ?
   LIMIT 1
`;

async function seedFoods(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    let inserted = 0;
    let updated = 0;
    let unchanged = 0;
    for (const f of FOODS) {
      const values = [f.category, f.servingDesc, f.kcal, f.proteinG, f.carbsG, f.fatG, f.fiberG, f.sugarG ?? null, f.sodiumMg ?? null];
      const [[own]] = await pool.query(FIND_OWN, [f.name]);
      if (!own) {
        await pool.query(
          `INSERT INTO foods (name, category, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [f.name, ...values],
        );
        inserted += 1;
        continue;
      }
      const [res] = await pool.query(
        `UPDATE foods SET category = ?, serving_desc = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?, fiber_g = ?, sugar_g = ?, sodium_mg = ?
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
