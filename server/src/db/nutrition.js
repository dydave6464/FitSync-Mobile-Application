'use strict';

const MEALS = ['breakfast', 'lunch', 'dinner', 'snack'];
const round2 = (n) => Math.round(Number(n) * 100) / 100;

function sourceOf(r) {
  if (r.food_id == null) return 'manual';
  return r.external_id ? 'fatsecret' : 'local';
}

function asEntry(r) {
  return {
    id: r.meal_log_id,
    mealType: r.meal_type,
    name: r.name,
    servingDesc: r.serving_desc,
    servings: Number(r.servings),
    kcal: r.calories,
    proteinG: round2(r.protein_g),
    carbsG: round2(r.carbs_g),
    fatG: round2(r.fat_g),
    source: sourceOf(r),
    foodId: r.food_id,
    externalId: r.external_id || null,
  };
}

const SELECT_ENTRY = `
  SELECT m.meal_log_id, m.meal_type, m.servings, m.calories, m.protein_g, m.carbs_g, m.fat_g,
         m.food_id, COALESCE(f.name, m.custom_name) AS name,
         COALESCE(m.serving_desc, f.serving_desc) AS serving_desc, s.external_id
    FROM meal_logs m
    LEFT JOIN foods f ON f.food_id = m.food_id
    LEFT JOIN food_sources s ON s.food_id = m.food_id
`;

/// [e]: { date, mealType, servings, foodId|null, customName|null, servingDesc|null,
/// kcal, proteinG, carbsG, fatG, loggedVia } -- numbers already multiplied.
async function insertEntry(pool, userId, e) {
  const [res] = await pool.query(
    `INSERT INTO meal_logs (user_id, food_id, custom_name, serving_desc, meal_type, servings,
                            calories, protein_g, carbs_g, fat_g, logged_via, log_date)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [userId, e.foodId, e.customName, e.servingDesc, e.mealType, e.servings,
      e.kcal, e.proteinG, e.carbsG, e.fatG, e.loggedVia, e.date],
  );
  return res.insertId;
}

async function getEntry(pool, userId, id) {
  const [rows] = await pool.query(`${SELECT_ENTRY} WHERE m.user_id = ? AND m.meal_log_id = ?`, [userId, id]);
  return rows.length ? asEntry(rows[0]) : null;
}

async function deleteEntry(pool, userId, id) {
  const [res] = await pool.query('DELETE FROM meal_logs WHERE user_id = ? AND meal_log_id = ?', [userId, id]);
  return res.affectedRows === 1;
}

async function listDayEntries(pool, userId, date) {
  const [rows] = await pool.query(
    `${SELECT_ENTRY} WHERE m.user_id = ? AND m.log_date = ? ORDER BY m.created_at, m.meal_log_id`,
    [userId, date],
  );
  return rows.map(asEntry);
}

/// What dailyTarget() needs, read straight from users. DATE_FORMAT so the
/// birthday arrives as the calendar date stored, not a zone-shifted instant.
async function targetProfile(pool, userId) {
  const [[u]] = await pool.query(
    `SELECT sex, DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS dob, height_cm, weight_kg,
            activity_level, main_goal
       FROM users WHERE user_id = ?`,
    [userId],
  );
  return {
    sex: u.sex,
    dateOfBirth: u.dob,
    heightCm: u.height_cm == null ? null : Number(u.height_cm),
    weightKg: u.weight_kg == null ? null : Number(u.weight_kg),
    activityLevel: u.activity_level,
    mainGoal: u.main_goal,
  };
}

/// The user's last [limit] distinct foods, newest first, as per-serving food
/// items. A catalogue or FatSecret food is one item however often it was
/// logged (its row's current numbers); a manual food is one item per name
/// (its latest entry's totals divided back by its servings).
async function listRecentFoods(pool, userId, limit = 20) {
  const [rows] = await pool.query(
    `SELECT * FROM (
       SELECT m.meal_log_id, m.created_at, m.food_id, m.custom_name, m.serving_desc AS m_serving,
              m.servings, m.calories, m.protein_g, m.carbs_g, m.fat_g,
              f.name AS f_name, f.serving_desc AS f_serving, f.calories AS f_kcal,
              f.protein_g AS f_protein, f.carbs_g AS f_carbs, f.fat_g AS f_fat, s.external_id,
              ROW_NUMBER() OVER (
                PARTITION BY COALESCE(CONCAT('f', m.food_id), CONCAT('m', m.custom_name))
                ORDER BY m.created_at DESC, m.meal_log_id DESC
              ) AS rn
         FROM meal_logs m
         LEFT JOIN foods f ON f.food_id = m.food_id
         LEFT JOIN food_sources s ON s.food_id = m.food_id
        WHERE m.user_id = ?
     ) x
     WHERE rn = 1
     ORDER BY created_at DESC, meal_log_id DESC
     LIMIT ?`,
    [userId, limit],
  );
  return rows.map((r) => {
    if (r.food_id != null) {
      return {
        id: r.food_id, source: r.external_id ? 'fatsecret' : 'local', externalId: r.external_id || null,
        name: r.f_name, servingDesc: r.f_serving, kcal: r.f_kcal,
        proteinG: round2(r.f_protein), carbsG: round2(r.f_carbs), fatG: round2(r.f_fat),
      };
    }
    const n = Number(r.servings);
    return {
      id: null, source: 'manual', externalId: null, name: r.custom_name, servingDesc: r.m_serving,
      kcal: Math.round(r.calories / n),
      proteinG: round2(r.protein_g / n), carbsG: round2(r.carbs_g / n), fatG: round2(r.fat_g / n),
    };
  });
}

module.exports = {
  MEALS, insertEntry, getEntry, deleteEntry, listDayEntries, targetProfile, listRecentFoods,
};
