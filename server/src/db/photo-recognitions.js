'use strict';

/// How many photos [userId] sent today (Manila) that count against the
/// daily limit: those the AI answered, with items or without. 'failed' rows
/// -- the AI busy or down -- are the service's fault and never count. The
/// pool runs at +08:00, so CURDATE() is Manila's today.
async function countToday(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS n FROM photo_recognitions
      WHERE user_id = ? AND status IN ('recognised', 'empty')
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

module.exports = { countToday, insertFailed, insertRecognition, readForLog, outcomesFor, markLogged };
