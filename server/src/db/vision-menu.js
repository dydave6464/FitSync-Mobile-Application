'use strict';
const { asFood } = require('./foods');

const FATSECRET_MENU_LIMIT = 100;
const MENU_TTL_MS = 10 * 60 * 1000;

const COLUMNS = `f.food_id, f.name, f.serving_desc, f.calories, f.protein_g, f.carbs_g, f.fat_g,
                 f.fiber_g, f.sugar_g, f.sodium_mg, f.food_type`;

/// The foods the AI may name: every FitSync food in the list's own order,
/// then the [fatsecretLimit] FatSecret copies logged most often (by anyone).
/// A copy whose name matches an earlier food, ignoring case, is left out --
/// FitSync's own numbers win. About 3,000 tokens of names at 244 foods.
async function loadMenuFoods(pool, { fatsecretLimit = FATSECRET_MENU_LIMIT } = {}) {
  const [own] = await pool.query(
    `SELECT ${COLUMNS}, NULL AS external_id
       FROM foods f LEFT JOIN food_sources s ON s.food_id = f.food_id
      WHERE s.food_id IS NULL
      ORDER BY f.list_order IS NULL, f.list_order, f.food_id`,
  );
  const [theirs] = await pool.query(
    `SELECT ${COLUMNS}, s.external_id
       FROM (SELECT food_id, COUNT(*) AS uses FROM meal_logs WHERE food_id IS NOT NULL GROUP BY food_id) u
       JOIN foods f ON f.food_id = u.food_id
       JOIN food_sources s ON s.food_id = f.food_id
      ORDER BY u.uses DESC, f.food_id
      LIMIT ?`,
    [fatsecretLimit],
  );
  const seen = new Set();
  const menu = [];
  for (const row of [...own, ...theirs]) {
    const name = row.name.trim().toLowerCase();
    if (seen.has(name)) continue;
    seen.add(name);
    menu.push(asFood(row));
  }
  return menu;
}

/// The menu, kept for [ttlMs] (10 minutes): a seed run or a newly popular
/// FatSecret food reaches the AI within that. Callers arriving while it
/// loads share the one load.
function createMenuCache({ ttlMs = MENU_TTL_MS, now = Date.now, load = loadMenuFoods } = {}) {
  let menu = null;
  let loadedAt = 0;
  let pending = null;
  return {
    async get(pool) {
      if (menu && now() - loadedAt < ttlMs) return menu;
      if (!pending) {
        pending = load(pool)
          .then((m) => {
            menu = m;
            loadedAt = now();
            return m;
          })
          .finally(() => {
            pending = null;
          });
      }
      return pending;
    },
  };
}

module.exports = { loadMenuFoods, createMenuCache, FATSECRET_MENU_LIMIT };
