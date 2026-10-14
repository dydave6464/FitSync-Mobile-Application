'use strict';

const round2 = (n) => Math.round(Number(n) * 100) / 100;

function asFood(r) {
  return {
    foodId: r.food_id,
    name: r.name,
    servingDesc: r.serving_desc,
    kcal: r.calories,
    proteinG: round2(r.protein_g),
    carbsG: round2(r.carbs_g),
    fatG: round2(r.fat_g),
    externalId: r.external_id || null,
  };
}

const SELECT_FOOD = `
  SELECT f.food_id, f.name, f.serving_desc, f.calories, f.protein_g, f.carbs_g, f.fat_g, s.external_id
    FROM foods f LEFT JOIN food_sources s ON s.food_id = f.food_id
`;

async function findFood(pool, foodId) {
  const [rows] = await pool.query(`${SELECT_FOOD} WHERE f.food_id = ?`, [foodId]);
  return rows.length ? asFood(rows[0]) : null;
}

/// FitSync's own foods (never FatSecret copies) whose name contains [q];
/// names starting with it first. LIKE wildcards in [q] are escaped.
async function searchOwnFoods(pool, q, limit = 20) {
  const esc = q.replace(/[\\%_]/g, (c) => `\\${c}`);
  const [rows] = await pool.query(
    `${SELECT_FOOD}
      WHERE s.food_id IS NULL AND f.name LIKE ?
      ORDER BY (f.name LIKE ?) DESC, f.name
      LIMIT ?`,
    [`%${esc}%`, `${esc}%`, limit],
  );
  return rows.map(asFood);
}

/// The foods row for a FatSecret food: created the first time anyone logs it,
/// refreshed with FatSecret's current numbers every time after. Returns its id.
async function upsertFatsecretFood(pool, food, retry = true) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[existing]] = await conn.query(
      "SELECT food_id FROM food_sources WHERE provider = 'fatsecret' AND external_id = ? FOR UPDATE",
      [food.externalId],
    );
    const values = [food.name.slice(0, 255), food.servingDesc, food.kcal, food.proteinG, food.carbsG, food.fatG];
    let foodId;
    if (existing) {
      foodId = existing.food_id;
      await conn.query(
        'UPDATE foods SET name = ?, serving_desc = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ? WHERE food_id = ?',
        [...values, foodId],
      );
    } else {
      const [ins] = await conn.query(
        `INSERT INTO foods (name, serving_desc, calories, protein_g, carbs_g, fat_g, category)
         VALUES (?, ?, ?, ?, ?, ?, 'international')`,
        values,
      );
      foodId = ins.insertId;
      await conn.query(
        "INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', ?)",
        [foodId, food.externalId],
      );
    }
    await conn.commit();
    return foodId;
  } catch (err) {
    await conn.rollback();
    // Two first-time logs of the same food raced; the other one won. Once.
    if (retry && err.code === 'ER_DUP_ENTRY') return upsertFatsecretFood(pool, food, false);
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { findFood, searchOwnFoods, upsertFatsecretFood, asFood };
