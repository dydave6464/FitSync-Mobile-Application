'use strict';

const round2 = (n) => Math.round(Number(n) * 100) / 100;
const nullable2 = (n) => (n == null ? null : round2(n));
const nullable1 = (n) => (n == null ? null : Math.round(Number(n) * 10) / 10);

function asFood(r) {
  return {
    foodId: r.food_id,
    name: r.name,
    servingDesc: r.serving_desc,
    kcal: r.calories,
    proteinG: round2(r.protein_g),
    carbsG: round2(r.carbs_g),
    fatG: round2(r.fat_g),
    fiberG: nullable2(r.fiber_g),
    sugarG: nullable2(r.sugar_g),
    sodiumMg: nullable1(r.sodium_mg),
    externalId: r.external_id || null,
  };
}

const SELECT_FOOD = `
  SELECT f.food_id, f.name, f.serving_desc, f.calories, f.protein_g, f.carbs_g, f.fat_g, f.fiber_g, f.sugar_g, f.sodium_mg, s.external_id
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
///
/// The lookup is a plain SELECT, not SELECT ... FOR UPDATE: on a key that
/// isn't there yet InnoDB takes a gap lock, and two first-time copies holding
/// one each block each other's INSERT -- a deadlock, never the duplicate key a
/// retry could recover from. The unique key on food_sources decides the race
/// instead: the loser's INSERT fails with ER_DUP_ENTRY, its foods row rolls
/// back with it, and its one retry finds the winner's row.
async function upsertFatsecretFood(pool, food, retry = true) {
  const servingDesc = food.servingDesc == null ? null : String(food.servingDesc).slice(0, 255);
  const values = [
    food.name.slice(0, 255), servingDesc, food.kcal, food.proteinG, food.carbsG, food.fatG,
    food.fiberG ?? null, food.sugarG ?? null, food.sodiumMg ?? null,
  ];
  const [[existing]] = await pool.query(
    "SELECT food_id FROM food_sources WHERE provider = 'fatsecret' AND external_id = ?",
    [food.externalId],
  );
  if (existing) {
    await pool.query(
      'UPDATE foods SET name = ?, serving_desc = ?, calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?, fiber_g = ?, sugar_g = ?, sodium_mg = ? WHERE food_id = ?',
      [...values, existing.food_id],
    );
    return existing.food_id;
  }
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [ins] = await conn.query(
      `INSERT INTO foods (name, serving_desc, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, category)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'international')`,
      values,
    );
    await conn.query(
      "INSERT INTO food_sources (food_id, provider, external_id) VALUES (?, 'fatsecret', ?)",
      [ins.insertId, food.externalId],
    );
    await conn.commit();
    return ins.insertId;
  } catch (err) {
    await conn.rollback();
    // Another first-time copy of the same food won (ER_DUP_ENTRY), or InnoDB
    // chose this transaction to break a lock wait (ER_LOCK_DEADLOCK, which
    // the plain SELECT should make rare). Once: the retry reads the winner.
    if (retry && (err.code === 'ER_DUP_ENTRY' || err.code === 'ER_LOCK_DEADLOCK')) {
      return upsertFatsecretFood(pool, food, false);
    }
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { findFood, searchOwnFoods, upsertFatsecretFood, asFood };
