'use strict';
const AppError = require('../lib/app-error');

/// "Don't suggest this" (Meal ideas round 2, spec 2026-11-13, 2.3): the
/// dishes a trainee asked not to be suggested.

const notFound = () => AppError.notFound('FOOD_NOT_FOUND', 'No such food.');

/// The list, newest first, leaving out foods the admin hid from everyone.
async function listHidden(pool, userId) {
  const [rows] = await pool.query(
    `SELECT h.food_id, f.name, UNIX_TIMESTAMP(h.hidden_at) AS hidden_epoch
       FROM user_hidden_suggestions h JOIN foods f ON f.food_id = h.food_id
      WHERE h.user_id = ? AND f.hidden_at IS NULL
      ORDER BY h.hidden_at DESC, h.food_id DESC`,
    [userId],
  );
  return rows.map((r) => ({
    foodId: r.food_id,
    name: r.name,
    hiddenAt: new Date(Number(r.hidden_epoch) * 1000).toISOString(),
  }));
}

/// Every hidden food id, for the picker.
async function hiddenFoodIds(pool, userId) {
  const [rows] = await pool.query('SELECT food_id FROM user_hidden_suggestions WHERE user_id = ?', [userId]);
  return rows.map((r) => r.food_id);
}

/// [raw] as a food id: a positive whole number, or FOOD_NOT_FOUND.
function foodIdOf(raw) {
  if (!/^\d+$/.test(String(raw)) || Number(raw) < 1) throw notFound();
  return Number(raw);
}

/// Hides one of FitSync's own foods for [userId]; hiding twice is harmless.
async function hideFood(pool, userId, rawFoodId) {
  const foodId = foodIdOf(rawFoodId);
  const [[own]] = await pool.query(
    `SELECT 1 AS ok FROM foods f
      WHERE f.food_id = ? AND NOT EXISTS (SELECT 1 FROM food_sources s WHERE s.food_id = f.food_id)`,
    [foodId],
  );
  if (!own) throw notFound();
  await pool.query('INSERT IGNORE INTO user_hidden_suggestions (user_id, food_id) VALUES (?, ?)', [userId, foodId]);
}

/// Shows it again; showing a dish that was not hidden is harmless.
async function showFood(pool, userId, rawFoodId) {
  const foodId = foodIdOf(rawFoodId);
  await pool.query('DELETE FROM user_hidden_suggestions WHERE user_id = ? AND food_id = ?', [userId, foodId]);
}

module.exports = { listHidden, hiddenFoodIds, hideFood, showFood };
