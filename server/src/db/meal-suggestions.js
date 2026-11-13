'use strict';

/// What GET /nutrition/suggestions reads (spec 2026-11-09). The picker
/// (lib/meal-suggestions.js) decides; these only read.

/// A foods row as a dish or a rice: DECIMAL columns arrive as strings.
function asFood(r) {
  return {
    foodId: r.food_id,
    name: r.name,
    servingDesc: r.serving_desc,
    kcal: r.calories,
    proteinG: Number(r.protein_g),
    carbsG: Number(r.carbs_g),
    fatG: Number(r.fat_g),
  };
}

/// Every food trainees can see that is suggested for some meal, with its
/// meals and whether it comes with rice. All meals, not one: once today's
/// calories are reached the light options are the snack ones, whatever meal
/// was asked (rule 9), so the picker sorts by meal itself.
async function readSuggestionPool(pool) {
  const [rows] = await pool.query(
    `SELECT f.food_id, f.name, f.serving_desc, f.calories, f.protein_g, f.carbs_g, f.fat_g,
            f.suggest_meals, f.suggest_with_rice
       FROM foods f
      WHERE f.hidden_at IS NULL AND f.suggest_meals <> ''
      ORDER BY f.food_id`,
  );
  return rows.map((r) => ({
    ...asFood(r),
    meals: String(r.suggest_meals).split(','),
    withRice: Boolean(r.suggest_with_rice),
  }));
}

/// FitSync's own visible food named exactly "White rice" (seed: 1 cup
/// (160 g), 206 kcal), or null when it is hidden or gone: plates are then
/// the dish alone. Never a FatSecret copy, whatever it is called.
async function readRice(pool) {
  const [[row]] = await pool.query(
    `SELECT f.food_id, f.name, f.serving_desc, f.calories, f.protein_g, f.carbs_g, f.fat_g
       FROM foods f
      WHERE f.name COLLATE utf8mb4_bin = 'White rice' AND f.hidden_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)
      ORDER BY f.food_id
      LIMIT 1`,
  );
  return row ? asFood(row) : null;
}

/// The cups of white rice this user's plates carry (users.usual_rice_cups,
/// 049): 0 to 2 in halves, 1 unless they chose. DECIMAL arrives as a string.
async function readUsualRiceCups(pool, userId) {
  const [[row]] = await pool.query('SELECT usual_rice_cups FROM users WHERE user_id = ?', [userId]);
  return row ? Number(row.usual_rice_cups) : 1;
}

module.exports = { readSuggestionPool, readRice, readUsualRiceCups };
