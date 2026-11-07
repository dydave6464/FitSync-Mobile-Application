'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

const FILE = '047_revenue_payments.sql';

test('revenue payments schema (047)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('revenue_payments keeps plan, amount, method and the day only', async () => {
    const [rows] = await pool.query(
      `SELECT COLUMN_NAME AS name, COLUMN_TYPE AS type, IS_NULLABLE AS nullable, COLUMN_KEY AS k, EXTRA AS extra
         FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'revenue_payments' ORDER BY ORDINAL_POSITION`,
    );
    assert.deepEqual(rows.map((r) => [r.name, r.type, r.nullable, r.k, r.extra]), [
      ['payment_id', 'int', 'NO', 'PRI', ''],
      ['plan', "enum('monthly','annual')", 'NO', '', ''],
      ['amount_php', 'decimal(10,2)', 'NO', '', ''],
      ['method', 'varchar(20)', 'YES', '', ''],
      ['paid_on', 'date', 'NO', 'MUL', ''],
    ]);
  });

  await t.test('no foreign key: the copy outlives the payment and the user', async () => {
    const [fks] = await pool.query(
      `SELECT CONSTRAINT_NAME FROM information_schema.REFERENTIAL_CONSTRAINTS
        WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'revenue_payments'`,
    );
    assert.deepEqual(fks, []);
    const [idx] = await pool.query(
      "SHOW INDEX FROM revenue_payments WHERE Key_name = 'idx_revenue_payments_paid_on'",
    );
    assert.deepEqual(idx.map((r) => r.Column_name), ['paid_on']);
  });

  await t.test('the backfill copies paid payments (on their Manila day), not pending ones, and replays safely', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('back@b.com', 'x', 'B')",
    );
    // 2026-11-04T20:00:00Z is already 2026-11-05 in Manila. The pool's
    // sessions are +08:00, so the instant is written in Manila time.
    const [paid] = await pool.query(
      `INSERT INTO pro_payments (user_id, plan, amount_php, status, method, paid_at)
       VALUES (?, 'annual', 1788, 'paid', 'gcash', '2026-11-05 04:00:00')`, [u.insertId],
    );
    const [noMethod] = await pool.query(
      `INSERT INTO pro_payments (user_id, plan, amount_php, status, paid_at)
       VALUES (?, 'monthly', 249, 'paid', '2026-10-01 09:00:00')`, [u.insertId],
    );
    await pool.query(
      "INSERT INTO pro_payments (user_id, plan, amount_php) VALUES (?, 'monthly', 249)", [u.insertId],
    );

    // Run 047 again against these rows, as on a database that had payments
    // before it landed.
    await pool.query('DELETE FROM schema_migrations WHERE version = ?', [FILE]);
    await pool.query('DROP TABLE revenue_payments');
    assert.deepEqual(await migrate(testDbConfig()), [FILE]);

    const copies = async () => (await pool.query(
      `SELECT payment_id, plan, amount_php, method, DATE_FORMAT(paid_on, '%Y-%m-%d') AS paid_on
         FROM revenue_payments ORDER BY payment_id`,
    ))[0].map((r) => ({ ...r }));
    const expected = [
      { payment_id: paid.insertId, plan: 'annual', amount_php: '1788.00', method: 'gcash', paid_on: '2026-11-05' },
      { payment_id: noMethod.insertId, plan: 'monthly', amount_php: '249.00', method: null, paid_on: '2026-10-01' },
    ];
    assert.deepEqual(await copies(), expected);

    // A replay of the whole file (the runner never recorded it) adds nothing.
    await pool.query('DELETE FROM schema_migrations WHERE version = ?', [FILE]);
    assert.deepEqual(await migrate(testDbConfig()), [FILE]);
    assert.deepEqual(await copies(), expected);
  });
});
