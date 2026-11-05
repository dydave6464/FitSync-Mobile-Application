'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  countToday, countFailedToday, insertFailed, insertRecognition, readForLog, markLogged, outcomesFor,
} = require('../src/db/photo-recognitions');

test('photo recognitions in the database', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const user = async (email) => (await pool.query(
    'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)', [email, 'x', 'U'],
  ))[0].insertId;
  const a = await user('a@photo.test');
  const b = await user('b@photo.test');
  const [rice] = await pool.query("INSERT INTO foods (name, category, serving_desc, calories) VALUES ('White rice', 'filipino', '1 cup (160 g)', 206)");
  const [garlic] = await pool.query("INSERT INTO foods (name, category, serving_desc, calories) VALUES ('Garlic fried rice (sinangag)', 'filipino', '1 cup (160 g)', 299)");

  await t.test('countToday counts today\'s answered photos in Manila: not failed ones, not yesterday\'s, not another user\'s', async () => {
    // The pool runs at +08:00, so CURDATE() is Manila's today and
    // CURDATE() - 1 second is 23:59:59 yesterday in Manila.
    await pool.query(
      `INSERT INTO photo_recognitions (user_id, item_count, status, created_at) VALUES
         (?, 1, 'recognised', CURDATE()), (?, 0, 'empty', NOW()), (?, 0, 'failed', NOW()),
         (?, 1, 'recognised', CURDATE() - INTERVAL 1 SECOND), (?, 1, 'recognised', NOW())`,
      [a, a, a, a, b],
    );
    assert.equal(await countToday(pool, a), 2);
    assert.equal(await countToday(pool, b), 1);
  });

  await t.test('countFailedToday counts only today\'s failed tries in Manila: not answered ones, not yesterday\'s, not another user\'s', async () => {
    const c = await user('c@photo.test');
    const d = await user('d@photo.test');
    await pool.query(
      `INSERT INTO photo_recognitions (user_id, item_count, status, created_at) VALUES
         (?, 0, 'failed', CURDATE()), (?, 0, 'failed', NOW()), (?, 1, 'recognised', NOW()), (?, 0, 'empty', NOW()),
         (?, 0, 'failed', CURDATE() - INTERVAL 1 SECOND), (?, 0, 'failed', NOW())`,
      [c, c, c, c, c, d],
    );
    assert.equal(await countFailedToday(pool, c), 2);
    assert.equal(await countFailedToday(pool, d), 1);
    assert.equal(await countToday(pool, c), 2, 'the daily limit still counts only answered photos');
  });

  await t.test('insertFailed adds a failed row, which does not count', async () => {
    await insertFailed(pool, b);
    const [[row]] = await pool.query(
      "SELECT status, item_count FROM photo_recognitions WHERE user_id = ? ORDER BY recognition_id DESC LIMIT 1", [b],
    );
    assert.deepEqual([row.status, row.item_count], ['failed', 0]);
    assert.equal(await countToday(pool, b), 1);
  });

  await t.test('insertRecognition stores the items in screen order', async () => {
    const { recognitionId, itemIds } = await insertRecognition(pool, a, [
      { foodId: rice.insertId, name: 'White rice', confidence: 0.95, servings: 1.5, alternativeFoodIds: [garlic.insertId] },
      { foodId: null, name: 'Atchara (pickled papaya)', confidence: 0.4, servings: null, alternativeFoodIds: [] },
    ]);
    const [[rec]] = await pool.query('SELECT status, item_count, logged_at FROM photo_recognitions WHERE recognition_id = ?', [recognitionId]);
    assert.deepEqual([rec.status, rec.item_count, rec.logged_at], ['recognised', 2, null]);
    const [items] = await pool.query(
      'SELECT item_id, item_order, suggested_food_id, suggested_name, confidence, suggested_servings, alternative_food_ids, outcome FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order',
      [recognitionId],
    );
    assert.deepEqual(items.map((r) => r.item_id), itemIds);
    assert.deepEqual(items.map((r) => [r.item_order, r.suggested_food_id, r.suggested_name, Number(r.confidence), r.suggested_servings == null ? null : Number(r.suggested_servings), r.alternative_food_ids, r.outcome]), [
      [1, rice.insertId, 'White rice', 0.95, 1.5, [garlic.insertId], 'pending'],
      [2, null, 'Atchara (pickled papaya)', 0.4, null, [], 'pending'],
    ]);
  });

  await t.test('no items makes an empty recognition, which still counts', async () => {
    const before = await countToday(pool, b);
    const { recognitionId, itemIds } = await insertRecognition(pool, b, []);
    const [[rec]] = await pool.query('SELECT status, item_count FROM photo_recognitions WHERE recognition_id = ?', [recognitionId]);
    assert.deepEqual([rec.status, rec.item_count, itemIds], ['empty', 0, []]);
    assert.equal(await countToday(pool, b), before + 1);
  });

  await t.test('readForLog: the owner\'s recognition with its items; null for another user or a failed one', async () => {
    const { recognitionId, itemIds } = await insertRecognition(pool, a, [
      { foodId: rice.insertId, name: 'White rice', confidence: null, servings: 1, alternativeFoodIds: [] },
    ]);
    assert.deepEqual(await readForLog(pool, a, recognitionId), {
      loggedAt: null, items: [{ itemId: itemIds[0], suggestedFoodId: rice.insertId }],
    });
    assert.equal(await readForLog(pool, b, recognitionId), null);
    await insertFailed(pool, a);
    const [[failed]] = await pool.query("SELECT MAX(recognition_id) AS id FROM photo_recognitions WHERE status = 'failed' AND user_id = ?", [a]);
    assert.equal(await readForLog(pool, a, failed.id), null);
  });

  await t.test('markLogged stamps logged_at and every outcome', async () => {
    const { recognitionId, itemIds } = await insertRecognition(pool, a, [
      { foodId: rice.insertId, name: 'White rice', confidence: 0.9, servings: 1, alternativeFoodIds: [] },
      { foodId: garlic.insertId, name: 'Garlic fried rice (sinangag)', confidence: 0.5, servings: 1, alternativeFoodIds: [] },
    ]);
    const [log] = await pool.query(
      "INSERT INTO meal_logs (user_id, food_id, meal_type, servings, calories, logged_via, log_date) VALUES (?, ?, 'lunch', 1, 206, 'photo', CURDATE())",
      [a, rice.insertId],
    );
    const conn = await pool.getConnection();
    try {
      await markLogged(conn, recognitionId, [
        { itemId: itemIds[0], outcome: 'kept', loggedFoodId: rice.insertId, mealLogId: log.insertId },
        { itemId: itemIds[1], outcome: 'removed', loggedFoodId: null, mealLogId: null },
      ]);
    } finally { conn.release(); }
    const read = await readForLog(pool, a, recognitionId);
    assert.ok(read.loggedAt instanceof Date);
    const [items] = await pool.query('SELECT outcome, logged_food_id, meal_log_id FROM photo_recognition_items WHERE recognition_id = ? ORDER BY item_order', [recognitionId]);
    assert.deepEqual(items.map((r) => [r.outcome, r.logged_food_id, r.meal_log_id]), [
      ['kept', rice.insertId, log.insertId], ['removed', null, null],
    ]);
  });
});

test('outcomesFor: kept when its own food is logged, swapped for another, removed when not sent', () => {
  const suggestions = [
    { itemId: 1, suggestedFoodId: 10 }, { itemId: 2, suggestedFoodId: 20 },
    { itemId: 3, suggestedFoodId: 30 }, { itemId: 4, suggestedFoodId: null },
  ];
  const logged = [
    { itemId: 1, foodId: 10, mealLogId: 101 }, // same food: kept, whatever the servings
    { itemId: 2, foodId: 21, mealLogId: 102 }, // another food: swapped
    { itemId: 4, foodId: null, mealLogId: 104 }, // an unlisted item logged as a manual food: swapped
    { itemId: null, foodId: 50, mealLogId: 105 }, // added by the user: no suggestion to mark
  ];
  assert.deepEqual(outcomesFor(suggestions, logged), [
    { itemId: 1, outcome: 'kept', loggedFoodId: 10, mealLogId: 101 },
    { itemId: 2, outcome: 'swapped', loggedFoodId: 21, mealLogId: 102 },
    { itemId: 3, outcome: 'removed', loggedFoodId: null, mealLogId: null },
    { itemId: 4, outcome: 'swapped', loggedFoodId: null, mealLogId: 104 },
  ]);
});
