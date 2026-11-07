'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { manilaDay } = require('../src/lib/manila-day');
const { previousMonth } = require('../src/db/admin-stats');
const { createPayment, completePayment } = require('../src/db/pro');
const { deleteUser } = require('../src/db/account');

/// 'YYYY-MM' of the month after [ym].
function nextMonth(ym) {
  const [y, m] = ym.split('-').map(Number);
  return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
}

test('GET /admin/revenue', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth } = await createTestAdmin(pool);
  const revenue = async (query = '') =>
    (await request(app).get(`/api/v1/admin/revenue${query}`).set(auth).expect(200)).body.data;

  const thisMonth = manilaDay().slice(0, 7);
  const lastMonth = previousMonth(thisMonth);
  const threeBack = previousMonth(previousMonth(lastMonth));

  let seq = 0;
  const trainee = async (fullName) => {
    seq += 1;
    const [r] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', ?)", [`rev${seq}@example.com`, fullName],
    );
    return r.insertId;
  };
  // A paid payment and its revenue copy, paid on [paidOn]; with no userId,
  // a copy whose payment (and trainee) no longer exists.
  const paid = async ({ userId = null, plan, amount, method = null, paidOn }) => {
    let paymentId;
    if (userId) {
      const [r] = await pool.query(
        `INSERT INTO pro_payments (user_id, plan, amount_php, status, method, paid_at)
         VALUES (?, ?, ?, 'paid', ?, ?)`, [userId, plan, amount, method, `${paidOn} 10:00:00`],
      );
      paymentId = r.insertId;
    } else {
      paymentId = 100000 + seq;
      seq += 1;
    }
    await pool.query(
      'INSERT INTO revenue_payments (payment_id, plan, amount_php, method, paid_on) VALUES (?, ?, ?, ?, ?)',
      [paymentId, plan, amount, method, paidOn],
    );
    return paymentId;
  };
  const ad = async ({ title, advertiser, amount, startsOn, endsOn, active = 1 }) => (await pool.query(
    `INSERT INTO advertisements (title, image_url, advertiser, amount_php, starts_on, ends_on, is_active)
     VALUES (?, 'ads/a.jpg', ?, ?, ?, ?, ?)`, [title, advertiser, amount, startsOn, endsOn, active],
  ))[0].insertId;

  await t.test('a trainee token is refused', async () => {
    const id = await trainee('Not Admin');
    const token = signToken(id, TEST_JWT);
    const res = await request(app).get('/api/v1/admin/revenue')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('nothing recorded: zeros, six empty months and no first month', async () => {
    const data = await revenue();
    const six = [];
    for (let m = thisMonth, i = 0; i < 6; i += 1, m = previousMonth(m)) six.unshift(m);
    assert.deepEqual(data, {
      month: thisMonth,
      totalPhp: 0,
      previousTotalPhp: 0,
      pro: { totalPhp: 0, monthly: 0, annual: 0 },
      ads: { totalPhp: 0, count: 0 },
      lastSixMonths: six.map((month) => ({ month, proPhp: 0, adsPhp: 0 })),
      proPayments: [],
      adPayments: [],
      firstMonth: null,
    });
  });

  const ids = {};
  await t.test('a month: Pro by the day paid, ads by the day they start', async () => {
    const juan = await trainee('Juan Dela Cruz');
    const maria = await trainee('Maria Santos');
    ids.juanMonthly = await paid({ userId: juan, plan: 'monthly', amount: 249, method: 'gcash', paidOn: `${thisMonth}-01` });
    ids.mariaAnnual = await paid({ userId: maria, plan: 'annual', amount: 1788, method: 'card', paidOn: `${thisMonth}-02` });
    ids.deleted = await paid({ plan: 'monthly', amount: 249, method: 'paymaya', paidOn: `${thisMonth}-01` });
    ids.last = await paid({ userId: juan, plan: 'monthly', amount: 249, method: 'gcash', paidOn: `${lastMonth}-28` });
    ids.old = await paid({ userId: maria, plan: 'annual', amount: 1788, paidOn: `${threeBack}-15` });
    // A pending attempt has no copy and never counts.
    await pool.query("INSERT INTO pro_payments (user_id, plan, amount_php) VALUES (?, 'annual', 1788)", [juan]);

    ids.adNow = await ad({ title: 'Big sale', advertiser: 'Gym Co', amount: 1200, startsOn: `${thisMonth}-01`, endsOn: `${thisMonth}-28` });
    // Paused, but paid: it counts.
    ids.adPaused = await ad({ title: 'Shoes', advertiser: 'Run Co', amount: 300.5, startsOn: `${thisMonth}-01`, endsOn: `${thisMonth}-03`, active: 0 });
    ids.adLast = await ad({ title: 'Promo', advertiser: 'Juice Co', amount: 500, startsOn: `${lastMonth}-20`, endsOn: `${thisMonth}-05` });

    const data = await revenue(`?month=${thisMonth}`);
    assert.equal(data.month, thisMonth);
    assert.deepEqual(data.pro, { totalPhp: 2286, monthly: 2, annual: 1 });
    assert.deepEqual(data.ads, { totalPhp: 1500.5, count: 2 });
    assert.equal(data.totalPhp, 3786.5);
    assert.equal(data.previousTotalPhp, 749);
    assert.equal(data.firstMonth, threeBack);

    assert.equal(data.lastSixMonths.length, 6);
    assert.equal(data.lastSixMonths[5].month, thisMonth);
    assert.deepEqual(data.lastSixMonths[5], { month: thisMonth, proPhp: 2286, adsPhp: 1500.5 });
    assert.deepEqual(data.lastSixMonths[4], { month: lastMonth, proPhp: 249, adsPhp: 500 });
    assert.deepEqual(data.lastSixMonths[3], { month: previousMonth(lastMonth), proPhp: 0, adsPhp: 0 });
    assert.deepEqual(data.lastSixMonths[2], { month: threeBack, proPhp: 1788, adsPhp: 0 });
    for (let i = 1; i < 6; i += 1) {
      assert.equal(data.lastSixMonths[i - 1].month, previousMonth(data.lastSixMonths[i].month));
    }

    // Newest day first; on one day, the newer payment first.
    assert.deepEqual(data.proPayments, [
      { paymentId: ids.mariaAnnual, name: 'Maria Santos', plan: 'annual', method: 'card', amountPhp: 1788, paidOn: `${thisMonth}-02` },
      { paymentId: ids.deleted, name: null, plan: 'monthly', method: 'paymaya', amountPhp: 249, paidOn: `${thisMonth}-01` },
      { paymentId: ids.juanMonthly, name: 'Juan Dela Cruz', plan: 'monthly', method: 'gcash', amountPhp: 249, paidOn: `${thisMonth}-01` },
    ]);
    assert.deepEqual(data.adPayments, [
      { adId: ids.adNow, advertiser: 'Gym Co', title: 'Big sale', amountPhp: 1200, startsOn: `${thisMonth}-01`, endsOn: `${thisMonth}-28` },
      { adId: ids.adPaused, advertiser: 'Run Co', title: 'Shoes', amountPhp: 300.5, startsOn: `${thisMonth}-01`, endsOn: `${thisMonth}-03` },
    ]);
  });

  await t.test('no month asked for: this Manila month', async () => {
    const data = await revenue();
    assert.equal(data.month, thisMonth);
    assert.equal(data.totalPhp, 3786.5);
  });

  await t.test('an earlier month answers its own lists and totals', async () => {
    const data = await revenue(`?month=${lastMonth}`);
    assert.equal(data.month, lastMonth);
    assert.equal(data.totalPhp, 749);
    assert.equal(data.previousTotalPhp, 0);
    assert.deepEqual(data.pro, { totalPhp: 249, monthly: 1, annual: 0 });
    assert.deepEqual(data.ads, { totalPhp: 500, count: 1 });
    assert.equal(data.lastSixMonths[5].month, lastMonth);
    assert.deepEqual(data.proPayments.map((p) => p.paymentId), [ids.last]);
    assert.deepEqual(data.adPayments.map((a) => a.adId), [ids.adLast]);
    assert.equal(data.firstMonth, threeBack);
  });

  await t.test('a bad or future month is a 400 on month', async () => {
    for (const q of ['?month=2026-13', '?month=abc', '?month=2026-1', '?month=2026-00',
      `?month=${nextMonth(thisMonth)}`, `?month=${thisMonth}&month=${lastMonth}`]) {
      const res = await request(app).get(`/api/v1/admin/revenue${q}`).set(auth).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', q);
      assert.deepEqual(res.body.error.details, [{ field: 'month' }], q);
    }
  });

  await t.test('the first month counts an ad as well as a payment', async () => {
    const early = previousMonth(previousMonth(threeBack));
    await ad({ title: 'Early', advertiser: 'Old Co', amount: 100, startsOn: `${early}-10`, endsOn: `${early}-12` });
    assert.equal((await revenue()).firstMonth, early);
  });

  await t.test('deleting a trainee who paid this month leaves the total unchanged', async () => {
    const userId = await trainee('Leaving Soon');
    const paymentId = await createPayment(pool, { userId, plan: 'monthly', amountPhp: 249 });
    await completePayment(pool, { userId, paymentId, months: 1, method: 'gcash' });
    const before = await revenue();
    assert.equal(before.totalPhp, 3786.5 + 249);
    assert.equal(before.proPayments.find((p) => p.paymentId === paymentId).name, 'Leaving Soon');

    assert.equal(await deleteUser(pool, userId), true);
    const after = await revenue();
    assert.equal(after.totalPhp, before.totalPhp);
    assert.deepEqual(after.pro, before.pro);
    assert.deepEqual(after.proPayments.find((p) => p.paymentId === paymentId), {
      paymentId, name: null, plan: 'monthly', method: 'gcash', amountPhp: 249, paidOn: manilaDay(),
    });
  });
});
