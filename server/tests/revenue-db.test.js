'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createPayment, completePayment } = require('../src/db/pro');
const { deleteUser } = require('../src/db/account');
const { manilaDay } = require('../src/lib/manila-day');

test('revenue copies of paid Pro payments', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const user = async () => {
    seq += 1;
    return (await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'P')", [`r${seq}@b.com`],
    ))[0].insertId;
  };
  const copies = async (paymentId) => (await pool.query(
    `SELECT payment_id, plan, amount_php, method, DATE_FORMAT(paid_on, '%Y-%m-%d') AS paid_on
       FROM revenue_payments WHERE payment_id = ?`, [paymentId],
  ))[0].map((r) => ({ ...r }));

  await t.test('completing a pending payment writes one copy, dated today in Manila', async () => {
    const userId = await user();
    const paymentId = await createPayment(pool, { userId, plan: 'annual', amountPhp: 1788 });
    const done = await completePayment(pool, { userId, paymentId, months: 12, method: 'gcash' });
    assert.equal(done.added, true);
    assert.deepEqual(await copies(paymentId), [
      { payment_id: paymentId, plan: 'annual', amount_php: '1788.00', method: 'gcash', paid_on: manilaDay() },
    ]);
  });

  await t.test('a second confirmation of the same payment adds nothing', async () => {
    const userId = await user();
    const paymentId = await createPayment(pool, { userId, plan: 'monthly', amountPhp: 249 });
    await completePayment(pool, { userId, paymentId, months: 1, method: null });
    const again = await completePayment(pool, { userId, paymentId, months: 1, method: 'card' });
    assert.equal(again.added, false);
    assert.deepEqual(await copies(paymentId), [
      { payment_id: paymentId, plan: 'monthly', amount_php: '249.00', method: null, paid_on: manilaDay() },
    ]);
  });

  await t.test('a payment that is not completed writes nothing', async () => {
    const userId = await user();
    const other = await user();
    const paymentId = await createPayment(pool, { userId, plan: 'monthly', amountPhp: 249 });
    // Another user's payment: rolled back, null.
    assert.equal(await completePayment(pool, { userId: other, paymentId, months: 1, method: 'gcash' }), null);
    // A failure inside the transaction (a method too long for its column)
    // rolls everything back.
    await assert.rejects(
      () => completePayment(pool, { userId, paymentId, months: 1, method: 'x'.repeat(30) }),
    );
    assert.deepEqual(await copies(paymentId), []);
    const [[p]] = await pool.query('SELECT status FROM pro_payments WHERE payment_id = ?', [paymentId]);
    assert.equal(p.status, 'pending');
  });

  await t.test('a copy that cannot be written leaves the payment unpaid (one transaction)', async () => {
    const userId = await user();
    const paymentId = await createPayment(pool, { userId, plan: 'monthly', amountPhp: 249 });
    // Make the copy's own INSERT fail: the payment must not become paid and
    // no period may be added, so the copy is part of the same transaction.
    await pool.query('RENAME TABLE revenue_payments TO revenue_payments_off');
    try {
      await assert.rejects(
        () => completePayment(pool, { userId, paymentId, months: 1, method: 'gcash' }),
        /revenue_payments/,
      );
    } finally {
      await pool.query('RENAME TABLE revenue_payments_off TO revenue_payments');
    }
    const [[p]] = await pool.query('SELECT status, paid_at FROM pro_payments WHERE payment_id = ?', [paymentId]);
    assert.equal(p.status, 'pending');
    assert.equal(p.paid_at, null);
    const [subs] = await pool.query('SELECT 1 FROM subscriptions WHERE user_id = ?', [userId]);
    assert.equal(subs.length, 0);
    assert.deepEqual(await copies(paymentId), []);
  });

  await t.test('deleting the trainee leaves the copy', async () => {
    const userId = await user();
    const paymentId = await createPayment(pool, { userId, plan: 'monthly', amountPhp: 249 });
    await completePayment(pool, { userId, paymentId, months: 1, method: 'paymaya' });
    assert.equal(await deleteUser(pool, userId), true);
    const [gone] = await pool.query('SELECT 1 FROM pro_payments WHERE payment_id = ?', [paymentId]);
    assert.equal(gone.length, 0);
    assert.deepEqual(await copies(paymentId), [
      { payment_id: paymentId, plan: 'monthly', amount_php: '249.00', method: 'paymaya', paid_on: manilaDay() },
    ]);
  });
});
