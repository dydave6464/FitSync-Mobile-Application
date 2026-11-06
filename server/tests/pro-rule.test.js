'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { buildTestApp } = require('./helpers/test-app');
const { markEmailVerified, findUserById } = require('../src/db/users');
const { allowanceFor } = require('../src/db/ai-cue-allowance');
const { proStatus, createPayment, setCheckoutSession, findPayment, completePayment } = require('../src/db/pro');

test('who is Pro, and paying for it', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `pro${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'P' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    const login = await request(app).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    return { userId, auth: { Authorization: `Bearer ${login.body.data.token}` } };
  };
  // A period that ends [days] from now (negative: already ended).
  const period = (userId, days, { plan = 'monthly', status = 'active' } = {}) => pool.query(
    `INSERT INTO subscriptions (user_id, plan, price_php, status, started_at, expires_at)
     VALUES (?, ?, 249, ?, NOW() - INTERVAL 1 DAY, NOW() + INTERVAL ? DAY)`,
    [userId, plan, status, days],
  );
  const isPro = async (userId) => Boolean((await findUserById(pool, userId)).is_premium);

  await t.test('free, granted by hand, or a period that has not ended', async () => {
    const free = await freshUser();
    assert.equal(await isPro(free.userId), false);

    const granted = await freshUser();
    await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [granted.userId]);
    assert.equal(await isPro(granted.userId), true);

    const paid = await freshUser();
    await period(paid.userId, 10);
    assert.equal(await isPro(paid.userId), true);

    const ended = await freshUser();
    await period(ended.userId, -1);
    assert.equal(await isPro(ended.userId), false, 'a period that ended is not Pro -- no timer needed');

    const cancelled = await freshUser();
    await period(cancelled.userId, 10, { status: 'cancelled' });
    assert.equal(await isPro(cancelled.userId), false);
  });

  await t.test('every place that reads Pro follows the rule', async () => {
    const paid = await freshUser();
    await period(paid.userId, 10);
    const me = await request(app).get('/api/v1/auth/me').set(paid.auth).expect(200);
    assert.equal(me.body.data.user.isPremium, true);
    const profile = await request(app).get('/api/v1/profile').set(paid.auth).expect(200);
    assert.equal(profile.body.data.profile.isPremium, true);
    assert.equal(await allowanceFor(pool, paid.userId, 1), 'pro');

    const ended = await freshUser();
    await period(ended.userId, -1);
    assert.equal((await request(app).get('/api/v1/profile').set(ended.auth).expect(200)).body.data.profile.isPremium, false);
    assert.equal(await allowanceFor(pool, ended.userId, 1), 'available');
  });

  await t.test('proStatus says how the user is Pro', async () => {
    const free = await freshUser();
    assert.deepEqual(await proStatus(pool, free.userId), {
      pro: false, source: null, until: null, plan: null, method: null, endsSoon: false, nextPeriodStartsAt: null,
    });

    // Granted Pro has no end, but a paid period it also holds still decides
    // when a payment made now would begin.
    const granted = await freshUser();
    await pool.query('UPDATE users SET is_premium = 1 WHERE user_id = ?', [granted.userId]);
    await period(granted.userId, 2);
    const [[sub]] = await pool.query(
      'SELECT UNIX_TIMESTAMP(MAX(expires_at)) AS e FROM subscriptions WHERE user_id = ?', [granted.userId],
    );
    assert.deepEqual(await proStatus(pool, granted.userId), {
      pro: true, source: 'granted', until: null, plan: null, method: null, endsSoon: false,
      nextPeriodStartsAt: new Date(Number(sub.e) * 1000).toISOString(),
    });

    const paid = await freshUser();
    const paymentId = await createPayment(pool, { userId: paid.userId, plan: 'annual', amountPhp: 1788 });
    await completePayment(pool, { userId: paid.userId, paymentId, months: 12, method: 'gcash' });
    const s = await proStatus(pool, paid.userId);
    assert.equal(s.pro, true);
    assert.equal(s.source, 'paid');
    assert.equal(s.plan, 'annual');
    assert.equal(s.method, 'gcash');
    assert.equal(s.endsSoon, false);
    assert.equal(s.nextPeriodStartsAt, s.until);
    const days = (Date.parse(s.until) - Date.now()) / 86400000;
    assert.ok(days > 360 && days < 370, `a year from now, got ${days} days`);

    const soon = await freshUser();
    await period(soon.userId, 2);
    assert.equal((await proStatus(pool, soon.userId)).endsSoon, true);
  });

  await t.test('a payment row: created, given its checkout, found only by its owner', async () => {
    const a = await freshUser();
    const b = await freshUser();
    const paymentId = await createPayment(pool, { userId: a.userId, plan: 'monthly', amountPhp: 249 });
    await setCheckoutSession(pool, paymentId, 'cs_test_1');
    assert.deepEqual(await findPayment(pool, a.userId, paymentId), {
      paymentId, userId: a.userId, plan: 'monthly', amountPhp: 249, sessionId: 'cs_test_1',
      status: 'pending', method: null, subscriptionId: null,
    });
    assert.equal(await findPayment(pool, b.userId, paymentId), null);
  });

  await t.test('completing a payment adds one period, once', async () => {
    const u = await freshUser();
    const paymentId = await createPayment(pool, { userId: u.userId, plan: 'monthly', amountPhp: 249 });
    const first = await completePayment(pool, { userId: u.userId, paymentId, months: 1, method: 'card' });
    assert.equal(first.added, true);
    const again = await completePayment(pool, { userId: u.userId, paymentId, months: 1, method: 'card' });
    assert.deepEqual(again, { subscriptionId: first.subscriptionId, added: false });
    const [subs] = await pool.query(
      'SELECT plan, price_php, status, TIMESTAMPDIFF(DAY, NOW(), expires_at) AS days FROM subscriptions WHERE user_id = ?', [u.userId],
    );
    assert.equal(subs.length, 1);
    assert.equal(subs[0].plan, 'monthly');
    assert.equal(Number(subs[0].price_php), 249);
    assert.equal(subs[0].status, 'active');
    assert.ok(subs[0].days >= 27 && subs[0].days <= 31, `about a month, got ${subs[0].days}`);
    const p = await findPayment(pool, u.userId, paymentId);
    assert.equal(p.status, 'paid');
    assert.equal(p.method, 'card');
    assert.equal(p.subscriptionId, first.subscriptionId);
  });

  await t.test("paying early extends from the current end date; another user's payment is refused", async () => {
    const u = await freshUser();
    await period(u.userId, 10);
    const [[before]] = await pool.query('SELECT MAX(expires_at) AS ends FROM subscriptions WHERE user_id = ?', [u.userId]);
    const paymentId = await createPayment(pool, { userId: u.userId, plan: 'annual', amountPhp: 1788 });
    const done = await completePayment(pool, { userId: u.userId, paymentId, months: 12, method: 'paymaya' });
    const [[added]] = await pool.query(
      'SELECT started_at, TIMESTAMPDIFF(MONTH, started_at, expires_at) AS months FROM subscriptions WHERE subscription_id = ?',
      [done.subscriptionId],
    );
    assert.equal(added.started_at.getTime(), before.ends.getTime(), 'starts when the current period ends');
    assert.equal(added.months, 12);

    const other = await freshUser();
    assert.equal(await completePayment(pool, { userId: other.userId, paymentId, months: 12, method: 'gcash' }), null);
  });
});
