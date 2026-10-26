'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

async function columns(pool, table) {
  const [rows] = await pool.query(
    `SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, IS_NULLABLE AS nullable, COLUMN_DEFAULT AS dflt
       FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
    [table],
  );
  return Object.fromEntries(rows.map((r) => [r.name, r]));
}

test('pro payments schema (041)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const user = async (email) => (await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'P')", [email],
  ))[0].insertId;

  await t.test('pro_payments: one row per payment attempt', async () => {
    const c = await columns(pool, 'pro_payments');
    assert.deepEqual(Object.keys(c), [
      'payment_id', 'user_id', 'plan', 'amount_php', 'checkout_session_id', 'status', 'method',
      'subscription_id', 'created_at', 'paid_at',
    ]);
    assert.equal(c.plan.type, "enum('monthly','annual')");
    assert.equal(c.amount_php.type, 'decimal(10,2)');
    assert.equal(c.status.type, "enum('pending','paid')");
    assert.equal(c.status.dflt, 'pending');
    for (const n of ['checkout_session_id', 'method', 'subscription_id', 'paid_at']) assert.equal(c[n].nullable, 'YES', n);
  });

  await t.test('a payment goes with its user; the period it bought may go without it', async () => {
    const userId = await user('pay1@example.com');
    const [sub] = await pool.query(
      "INSERT INTO subscriptions (user_id, plan, price_php, expires_at) VALUES (?, 'monthly', 249, NOW() + INTERVAL 1 MONTH)", [userId],
    );
    const [pay] = await pool.query(
      "INSERT INTO pro_payments (user_id, plan, amount_php, status, subscription_id) VALUES (?, 'monthly', 249, 'paid', ?)",
      [userId, sub.insertId],
    );
    await pool.query('DELETE FROM subscriptions WHERE subscription_id = ?', [sub.insertId]);
    const [[kept]] = await pool.query('SELECT subscription_id FROM pro_payments WHERE payment_id = ?', [pay.insertId]);
    assert.equal(kept.subscription_id, null);
    await pool.query('DELETE FROM users WHERE user_id = ?', [userId]);
    const [gone] = await pool.query('SELECT 1 FROM pro_payments WHERE payment_id = ?', [pay.insertId]);
    assert.equal(gone.length, 0);
  });

  await t.test('one PayMongo checkout belongs to one payment', async () => {
    const userId = await user('pay2@example.com');
    const insert = () => pool.query(
      "INSERT INTO pro_payments (user_id, plan, amount_php, checkout_session_id) VALUES (?, 'annual', 1788, 'cs_same')", [userId],
    );
    await insert();
    await assert.rejects(insert(), (e) => e.code === 'ER_DUP_ENTRY');
  });
});
