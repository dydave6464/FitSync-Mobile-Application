'use strict';
const AppError = require('../lib/app-error');
const { likePattern } = require('../lib/query-params');
const { invalidAdminField } = require('../lib/admin-params');
const {
  checkManual, round1, round2, MAX_NAME, MAX_SERVING_DESC,
} = require('../lib/nutrition-input');
const { FOOD_TYPES } = require('./foods');

const SHOW = { shown: 'f.hidden_at IS NULL', hidden: 'f.hidden_at IS NOT NULL' };
const CATEGORIES = ['filipino', 'international'];
// The numbers that decide a food's calories (nutrition-input.js's rule).
const CALORIE_FIELDS = ['kcal', 'proteinG', 'carbsG', 'fatG'];
const NUMBER_FIELDS = [...CALORIE_FIELDS, 'fiberG', 'sugarG', 'sodiumMg'];

// FitSync's own foods: a FatSecret copy has a food_sources row.
const OWN = 'NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)';

const SELECT_FOOD = `
  SELECT f.food_id, f.name, f.category, f.food_type, f.serving_desc, f.calories, f.protein_g, f.carbs_g,
         f.fat_g, f.fiber_g, f.sugar_g, f.sodium_mg, f.hidden_at IS NOT NULL AS hidden
    FROM foods f`;

// DECIMAL columns arrive as strings.
const nullable2 = (n) => (n == null ? null : round2(Number(n)));
const nullable1 = (n) => (n == null ? null : round1(Number(n)));

/// A SELECT_FOOD row in Appendix A's admin food shape.
function asAdminFood(r) {
  return {
    id: r.food_id,
    name: r.name,
    category: r.category,
    foodType: r.food_type,
    servingDesc: r.serving_desc,
    kcal: r.calories,
    proteinG: round2(Number(r.protein_g)),
    carbsG: round2(Number(r.carbs_g)),
    fatG: round2(Number(r.fat_g)),
    fiberG: nullable2(r.fiber_g),
    sugarG: nullable2(r.sugar_g),
    sodiumMg: nullable1(r.sodium_mg),
    hidden: Boolean(r.hidden),
  };
}

function nameTaken() {
  return AppError.conflict('FOOD_NAME_TAKEN', 'A food with that name already exists.');
}

/// [food] with every field checked: name 1-100 and serving 1-60 characters
/// (trimmed), category and type from their lists (400 INVALID_ADMIN_FIELD),
/// and the numbers by the typed-food rule, checkManual (400
/// INVALID_NUTRITION_FIELD): typed calories are kept, none are worked out
/// from protein, carbs and fat, and a food with neither is refused.
function checkFood(food) {
  const name = typeof food.name === 'string' ? food.name.trim() : '';
  if (name.length < 1 || name.length > MAX_NAME) {
    throw invalidAdminField('name', `name must be 1 to ${MAX_NAME} characters.`);
  }
  if (!CATEGORIES.includes(food.category)) {
    throw invalidAdminField('category', 'category must be filipino or international.');
  }
  if (!FOOD_TYPES.includes(food.foodType)) {
    throw invalidAdminField('foodType', `foodType must be one of: ${FOOD_TYPES.join(', ')}.`);
  }
  const servingDesc = typeof food.servingDesc === 'string' ? food.servingDesc.trim() : '';
  if (servingDesc.length < 1 || servingDesc.length > MAX_SERVING_DESC) {
    throw invalidAdminField('servingDesc', `servingDesc must be 1 to ${MAX_SERVING_DESC} characters.`);
  }
  const numbers = Object.fromEntries(NUMBER_FIELDS.map((k) => [k, food[k]]));
  const checked = checkManual({ name, servingDesc: null, ...numbers });
  return {
    name,
    category: food.category,
    foodType: food.foodType,
    servingDesc,
    kcal: checked.kcal,
    proteinG: checked.proteinG,
    carbsG: checked.carbsG,
    fatG: checked.fatG,
    fiberG: checked.fiberG,
    sugarG: checked.sugarG,
    sodiumMg: checked.sodiumMg,
  };
}

/// One of FitSync's own foods (never a FatSecret copy), or null.
async function findOwnFood(pool, foodId) {
  const [[row]] = await pool.query(`${SELECT_FOOD} WHERE f.food_id = ? AND ${OWN}`, [foodId]);
  return row ? asAdminFood(row) : null;
}

/// Whether another of FitSync's own foods (not [exceptId]) is called [name].
/// The column's collation ignores case.
async function ownNameTaken(pool, name, exceptId = null) {
  const [rows] = await pool.query(
    `SELECT 1 FROM foods f WHERE f.name = ? AND f.food_id <> ? AND ${OWN} LIMIT 1`,
    [name, exceptId ?? 0],
  );
  return rows.length > 0;
}

/// One page of FitSync's own foods, shown or hidden ([show]), whose name
/// matches [q], in the food list's order, with the filtered total and the
/// shown and hidden counts of them all (the chips' numbers).
async function listAdminFoods(pool, { show, q = null, page = 1, limit = 30 }) {
  const where = [OWN, SHOW[show]];
  const params = [];
  if (q !== null && q.trim() !== '') {
    where.push('f.name LIKE ?');
    params.push(likePattern(q));
  }
  const whereSql = where.join(' AND ');
  const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM foods f WHERE ${whereSql}`, params);
  const [rows] = await pool.query(
    `${SELECT_FOOD} WHERE ${whereSql}
      ORDER BY f.list_order IS NULL, f.list_order, f.name, f.food_id
      LIMIT ? OFFSET ?`,
    [...params, limit, (page - 1) * limit],
  );
  const [[counts]] = await pool.query(
    `SELECT COALESCE(SUM(f.hidden_at IS NULL), 0) AS shown, COALESCE(SUM(f.hidden_at IS NOT NULL), 0) AS hidden
       FROM foods f WHERE ${OWN}`,
  );
  return {
    foods: rows.map(asAdminFood),
    counts: { shown: Number(counts.shown), hidden: Number(counts.hidden) },
    total: Number(total),
  };
}

const WRITE_COLUMNS = `name = ?, category = ?, food_type = ?, serving_desc = ?, calories = ?, protein_g = ?,
  carbs_g = ?, fat_g = ?, fiber_g = ?, sugar_g = ?, sodium_mg = ?, added_by = ?`;
const writeValues = (f, adminId) => [
  f.name, f.category, f.foodType, f.servingDesc, f.kcal, f.proteinG, f.carbsG, f.fatG, f.fiberG, f.sugarG,
  f.sodiumMg, adminId,
];

/// Adds one of FitSync's own foods, added by [adminId]. 400 per bad field;
/// 409 FOOD_NAME_TAKEN when another own food has the name, in any case.
async function createFood(pool, input, adminId) {
  const food = checkFood(input);
  if (await ownNameTaken(pool, food.name)) throw nameTaken();
  const [r] = await pool.query(`INSERT INTO foods SET ${WRITE_COLUMNS}`, writeValues(food, adminId));
  return findOwnFood(pool, r.insertId);
}

/// Changes the fields [input] sends of one of FitSync's own foods and marks
/// it as [adminId]'s (so the seed leaves it alone). Calories follow the
/// typed-food rule again when any of kcal, protein, carbs or fat is sent;
/// otherwise they stay. Meals already logged keep their own numbers. null
/// when there is no such own food.
async function updateFood(pool, foodId, input, adminId) {
  const existing = await findOwnFood(pool, foodId);
  if (!existing) return null;
  const sent = (k) => Object.hasOwn(input, k);
  const merged = Object.fromEntries(
    ['name', 'category', 'foodType', 'servingDesc', ...NUMBER_FIELDS]
      .map((k) => [k, sent(k) ? input[k] : existing[k]]),
  );
  // Sent without kcal (or kcal null): worked out from protein, carbs and fat.
  if (CALORIE_FIELDS.some(sent)) merged.kcal = input.kcal;
  const food = checkFood(merged);
  if (await ownNameTaken(pool, food.name, foodId)) throw nameTaken();
  await pool.query(`UPDATE foods SET ${WRITE_COLUMNS} WHERE food_id = ?`, [...writeValues(food, adminId), foodId]);
  return findOwnFood(pool, foodId);
}

/// Hides one of FitSync's own foods (from search, Recents and Snap a meal)
/// or shows it again. Hiding a hidden food keeps when it was hidden. null
/// when there is no such own food.
async function setFoodHidden(pool, foodId, hidden) {
  const [r] = await pool.query(
    `UPDATE foods f SET f.hidden_at = ${hidden ? 'COALESCE(f.hidden_at, NOW())' : 'NULL'}
      WHERE f.food_id = ? AND ${OWN}`,
    [foodId],
  );
  return r.affectedRows === 0 ? null : findOwnFood(pool, foodId);
}

module.exports = {
  SHOW, asAdminFood, listAdminFoods, findOwnFood, createFood, updateFood, setFoodHidden,
};
