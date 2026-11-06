'use strict';

/// How many photos [userId] sent today (Manila) that count against the
/// daily limit: those the AI found food in. 'empty' rows (no food found) and
/// 'failed' rows (the AI busy or down) never count. The pool runs at +08:00,
/// so CURDATE() is Manila's today.
async function countToday(pool, userId) {
  return countTodayWhere(pool, userId, "status = 'recognised'");
}

/// How many photos [userId] sent today (Manila) that cost no photo: the AI
/// failed on them or found no food. They never count against the daily
/// limit, but each cost a full AI call, so the route caps them separately.
async function countFreeTriesToday(pool, userId) {
  return countTodayWhere(pool, userId, "status IN ('failed', 'empty')");
}

/// [userId]'s rows created today (Manila) that match [statusCondition], a
/// fixed SQL condition on status -- never user input.
async function countTodayWhere(pool, userId, statusCondition) {
  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS n FROM photo_recognitions
      WHERE user_id = ? AND ${statusCondition}
        AND created_at >= CURDATE() AND created_at < CURDATE() + INTERVAL 1 DAY`,
    [userId],
  );
  return Number(row.n);
}

async function insertFailed(pool, userId) {
  await pool.query("INSERT INTO photo_recognitions (user_id, item_count, status) VALUES (?, 0, 'failed')", [userId]);
}

/// One answered photo and its items, in one transaction. [rows]:
/// { foodId|null, name, confidence|null, servings|null, alternativeFoodIds }
/// in screen order. No rows makes an 'empty' recognition.
async function insertRecognition(pool, userId, rows) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rec] = await conn.query(
      'INSERT INTO photo_recognitions (user_id, item_count, status) VALUES (?, ?, ?)',
      [userId, rows.length, rows.length ? 'recognised' : 'empty'],
    );
    const itemIds = [];
    for (const [i, r] of rows.entries()) {
      const [ins] = await conn.query(
        `INSERT INTO photo_recognition_items
           (recognition_id, item_order, suggested_food_id, suggested_name, confidence, suggested_servings, alternative_food_ids)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [rec.insertId, i + 1, r.foodId, r.name.slice(0, 255), r.confidence, r.servings, JSON.stringify(r.alternativeFoodIds)],
      );
      itemIds.push(ins.insertId);
    }
    await conn.commit();
    return { recognitionId: rec.insertId, itemIds };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

/// The recognition a log names, with its items -- or null when it is
/// missing, another user's, or a failed attempt (whose id the app never
/// got). With [lock], inside a transaction, the row is held FOR UPDATE so
/// two logs of one photo can't both pass the logged_at check.
async function readForLog(db, userId, recognitionId, { lock = false } = {}) {
  const [[rec]] = await db.query(
    `SELECT logged_at FROM photo_recognitions
      WHERE recognition_id = ? AND user_id = ? AND status <> 'failed'${lock ? ' FOR UPDATE' : ''}`,
    [recognitionId, userId],
  );
  if (!rec) return null;
  const [items] = await db.query(
    'SELECT item_id, suggested_food_id FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order',
    [recognitionId],
  );
  return {
    loggedAt: rec.logged_at,
    items: items.map((r) => ({ itemId: r.item_id, suggestedFoodId: r.suggested_food_id })),
  };
}

/// [userId]'s newest recognised photo today (Manila), with its items in
/// screen order -- or null when there is none. Empty and failed rows are
/// skipped. It is the newest even when it is logged (loggedAt set): an older
/// unlogged photo is never offered instead. foodId is null for an item not
/// on FitSync's list, or one whose food has since been deleted.
async function readLatestToday(pool, userId) {
  const [[rec]] = await pool.query(
    `SELECT recognition_id, created_at, logged_at FROM photo_recognitions
      WHERE user_id = ? AND status = 'recognised'
        AND created_at >= CURDATE() AND created_at < CURDATE() + INTERVAL 1 DAY
      ORDER BY created_at DESC, recognition_id DESC LIMIT 1`,
    [userId],
  );
  if (!rec) return null;
  const [items] = await pool.query(
    `SELECT item_id, suggested_food_id, suggested_name, confidence, suggested_servings, alternative_food_ids
       FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order`,
    [rec.recognition_id],
  );
  const num = (n) => (n == null ? null : Number(n));
  return {
    recognitionId: rec.recognition_id,
    createdAt: rec.created_at,
    loggedAt: rec.logged_at,
    items: items.map((r) => ({
      itemId: r.item_id,
      foodId: r.suggested_food_id,
      name: r.suggested_name,
      confidence: num(r.confidence),
      servings: num(r.suggested_servings),
      alternativeFoodIds: r.alternative_food_ids,
    })),
  };
}

/// Every suggestion's outcome once the photo is logged. [suggestions]:
/// { itemId, suggestedFoodId|null }; [logged]: { itemId|null, foodId|null,
/// mealLogId }. kept: the suggested food was logged (servings may differ);
/// swapped: something else was logged in its place (an unlisted item is
/// always swapped); removed: nothing was sent for it. Entries the user added
/// (itemId null) mark nothing.
function outcomesFor(suggestions, logged) {
  return suggestions.map((s) => {
    const l = logged.find((x) => x.itemId === s.itemId);
    if (!l) return { itemId: s.itemId, outcome: 'removed', loggedFoodId: null, mealLogId: null };
    const kept = s.suggestedFoodId != null && l.foodId === s.suggestedFoodId;
    return { itemId: s.itemId, outcome: kept ? 'kept' : 'swapped', loggedFoodId: l.foodId, mealLogId: l.mealLogId };
  });
}

/// Inside the log's transaction: stamps the photo as logged and writes each
/// suggestion's outcome (from outcomesFor).
async function markLogged(conn, recognitionId, outcomes) {
  await conn.query('UPDATE photo_recognitions SET logged_at = CURRENT_TIMESTAMP WHERE recognition_id = ?', [recognitionId]);
  for (const o of outcomes) {
    await conn.query(
      `UPDATE photo_recognition_items SET outcome = ?, logged_food_id = ?, meal_log_id = ?
        WHERE item_id = ? AND recognition_id = ?`,
      [o.outcome, o.loggedFoodId, o.mealLogId, o.itemId, recognitionId],
    );
  }
}

module.exports = {
  countToday, countFreeTriesToday, insertFailed, insertRecognition, readForLog, readLatestToday, outcomesFor, markLogged,
};
