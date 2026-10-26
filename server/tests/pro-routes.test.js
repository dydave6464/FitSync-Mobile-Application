'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { buildTestApp } = require('./helpers/test-app');
const { markEmailVerified } = require('../src/db/users');
const { createPaymentsService } = require('../src/services/payments');
const { PaymentsError } = require('../src/services/payments/errors');

test('/api/v1/pro', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const stub = createPaymentsService({});
  const app = buildTestApp({ pool, payments: stub });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const freshUser = async (on = app) => {
    seq += 1;
    const email = `buy${seq}@example.com`;
    const reg = await request(on).post('/api/v1/auth/register').send({ email, password: 's3cret-pass', fullName: 'B' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    const login = await request(on).post('/api/v1/auth/login').send({ email, password: 's3cret-pass' }).expect(200);
    const auth = { Authorization: `Bearer ${login.body.data.token}` };
    return {
      userId,
      status: () => request(on).get('/api/v1/pro').set(auth),
      checkout: (body) => request(on).post('/api/v1/pro/checkout').set(auth).send(body),
      confirm: (id) => request(on).post(`/api/v1/pro/payments/${id}/confirm`).set(auth).send({}),
      profile: () => request(on).get('/api/v1/profile').set(auth),
    };
  };
  // Clicks the stub page's button, the way the browser would.
  const stubClick = (checkoutUrl, action) => {
    const path = new URL(checkoutUrl).pathname;
    return request(app).post(path).type('form').send({ action });
  };
  // Times through UNIX_TIMESTAMP(): a raw DATETIME comes back in the session's
  // +08:00 zone labelled as UTC (db/pool.js), 8 hours off the API's ISO time.
  const subsOf = async (userId) => (await pool.query(
    `SELECT plan, price_php, UNIX_TIMESTAMP(started_at) AS started_epoch, UNIX_TIMESTAMP(expires_at) AS expires_epoch
       FROM subscriptions WHERE user_id = ? ORDER BY subscription_id`, [userId],
  ))[0].map(({ started_epoch: s, expires_epoch: e, ...r }) => ({
    ...r, started_at: new Date(Number(s) * 1000), expires_at: new Date(Number(e) * 1000),
  }));

  await t.test('signed out is 401; a free user sees no Pro and the prices', async () => {
    await request(app).get('/api/v1/pro').expect(401);
    const u = await freshUser();
    const res = await u.status().expect(200);
    assert.deepEqual(res.body.data, {
      pro: false, source: null, until: null, plan: null, method: null, endsSoon: false,
      prices: { monthly: 249, annual: 1788 },
    });
  });

  await t.test('checkout refuses an unknown plan', async () => {
    const u = await freshUser();
    for (const plan of ['weekly', 'constructor', '__proto__', 5, undefined]) {
      const res = await u.checkout({ plan }).expect(400);
      assert.equal(res.body.error.code, 'INVALID_PLAN');
    }
  });

  await t.test("checkout charges the server's price and comes back to the address the app used", async () => {
    const u = await freshUser();
    const res = await u.checkout({ plan: 'monthly', amount: 1, price: 1 }).expect(201);
    const { paymentId, checkoutUrl } = res.body.data;
    assert.ok(Number.isInteger(paymentId));
    assert.match(checkoutUrl, /^http:\/\/127\.0\.0\.1:\d+\/api\/v1\/pro\/stub-checkout\/stub_fitsync-\d+_\d+$/);
    const sessionId = checkoutUrl.split('/').pop();
    assert.deepEqual(stub.session(sessionId), { name: 'FitSync Pro — 1 month', amountCentavos: 24900 });
    const [[row]] = await pool.query('SELECT status, plan, amount_php, checkout_session_id FROM pro_payments WHERE payment_id = ?', [paymentId]);
    assert.deepEqual({ ...row, amount_php: Number(row.amount_php) }, { status: 'pending', plan: 'monthly', amount_php: 249, checkout_session_id: sessionId });
  });

  await t.test('a real PUBLIC_BASE_URL is used for the return page; localhost is not', async () => {
    const seen = [];
    const capture = { mode: 'test', async createCheckout(a) { seen.push(a); return { sessionId: `cs_${seen.length}`, checkoutUrl: 'https://checkout.paymongo.com/x' }; }, async getCheckout() { return { paid: false }; } };
    const pub = buildTestApp({ pool, payments: capture, publicBaseUrl: 'https://fitsync.example' });
    const u = await freshUser(pub);
    const res = await u.checkout({ plan: 'annual' }).expect(201);
    const id = res.body.data.paymentId;
    assert.equal(seen[0].successUrl, `https://fitsync.example/api/v1/pro/return?payment=${id}&result=success`);
    assert.equal(seen[0].cancelUrl, `https://fitsync.example/api/v1/pro/return?payment=${id}&result=cancel`);
    assert.equal(seen[0].amountCentavos, 178800);
    assert.equal(seen[0].referenceNumber, `fitsync-${id}`);
  });

  await t.test('with payments off, checkout is 503; when PayMongo fails, 502 and the attempt stays pending', async () => {
    const off = buildTestApp({ pool, payments: null });
    const u1 = await freshUser(off);
    assert.equal((await u1.checkout({ plan: 'monthly' }).expect(503)).body.error.code, 'PAYMENTS_UNAVAILABLE');

    const failing = { mode: 'test', async createCheckout() { throw new PaymentsError('PAYMENTS_UNAVAILABLE', { status: 401 }); }, async getCheckout() { return { paid: false }; } };
    const broken = buildTestApp({ pool, payments: failing });
    const u2 = await freshUser(broken);
    const res = await u2.checkout({ plan: 'monthly' }).expect(502);
    assert.equal(res.body.error.code, 'PAYMENTS_UNAVAILABLE');
    assert.equal(res.body.error.message, "Couldn't open the payment page. Try again.");
    const [rows] = await pool.query('SELECT status, checkout_session_id FROM pro_payments WHERE user_id = ?', [u2.userId]);
    assert.deepEqual(rows.map((r) => ({ ...r })), [{ status: 'pending', checkout_session_id: null }]);
  });

  await t.test('confirm: pending until paid, then Pro with an end date; twice adds one period', async () => {
    const u = await freshUser();
    const { paymentId, checkoutUrl } = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    const before = await u.confirm(paymentId).expect(200);
    assert.equal(before.body.data.status, 'pending');
    assert.equal(before.body.data.pro.pro, false);

    const back = await stubClick(checkoutUrl, 'authorize').expect(303);
    assert.match(back.headers.location, new RegExp(`/api/v1/pro/return\\?payment=${paymentId}&result=success$`));

    const paid = await u.confirm(paymentId).expect(200);
    assert.equal(paid.body.data.status, 'paid');
    const pro = paid.body.data.pro;
    assert.equal(pro.pro, true);
    assert.equal(pro.source, 'paid');
    assert.equal(pro.plan, 'monthly');
    assert.equal(pro.method, 'gcash');
    assert.deepEqual(pro.prices, { monthly: 249, annual: 1788 });
    const days = (Date.parse(pro.until) - Date.now()) / 86400000;
    assert.ok(days > 27 && days < 32, `about a month, got ${days}`);
    assert.equal((await u.profile().expect(200)).body.data.profile.isPremium, true, 'the app sees Pro at once');

    await u.confirm(paymentId).expect(200);
    assert.equal((await subsOf(u.userId)).length, 1, 'confirming again adds nothing');
  });

  await t.test('paying for a year early extends from the current end date', async () => {
    const u = await freshUser();
    const first = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    await stubClick(first.checkoutUrl, 'authorize').expect(303);
    await u.confirm(first.paymentId).expect(200);
    const second = (await u.checkout({ plan: 'annual' }).expect(201)).body.data;
    await stubClick(second.checkoutUrl, 'authorize').expect(303);
    const res = await u.confirm(second.paymentId).expect(200);
    const [a, b] = await subsOf(u.userId);
    assert.equal(b.started_at.getTime(), a.expires_at.getTime());
    assert.equal(res.body.data.pro.plan, 'annual');
    assert.equal(Date.parse(res.body.data.pro.until), b.expires_at.getTime());
  });

  await t.test('a failed payment stays pending', async () => {
    const u = await freshUser();
    const { paymentId, checkoutUrl } = (await u.checkout({ plan: 'annual' }).expect(201)).body.data;
    const back = await stubClick(checkoutUrl, 'fail').expect(303);
    assert.match(back.headers.location, /result=cancel$/);
    assert.equal((await u.confirm(paymentId).expect(200)).body.data.status, 'pending');
    assert.equal((await subsOf(u.userId)).length, 0);
  });

  await t.test("someone else's payment, or none, is 404", async () => {
    const owner = await freshUser();
    const other = await freshUser();
    const { paymentId } = (await owner.checkout({ plan: 'monthly' }).expect(201)).body.data;
    for (const id of [paymentId, 999999, 'abc', 0]) {
      assert.equal((await other.confirm(id).expect(404)).body.error.code, 'PAYMENT_NOT_FOUND');
    }
  });

  await t.test('a paid amount that is not our price is refused; PayMongo down is 502', async () => {
    let answer = { paid: true, amountCentavos: 100, currency: 'PHP', method: 'card' };
    const fake = { mode: 'test', async createCheckout() { return { sessionId: `cs_m${Date.now()}`, checkoutUrl: 'https://checkout.paymongo.com/x' }; }, async getCheckout() { if (answer instanceof Error) throw answer; return answer; } };
    const pm = buildTestApp({ pool, payments: fake });
    const u = await freshUser(pm);
    const { paymentId } = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    assert.equal((await u.confirm(paymentId).expect(409)).body.error.code, 'PAYMENT_MISMATCH');
    answer = { paid: true, amountCentavos: 24900, currency: 'USD', method: 'card' };
    await u.confirm(paymentId).expect(409);
    assert.equal((await subsOf(u.userId)).length, 0);
    answer = new PaymentsError('PAYMENTS_UNAVAILABLE', { status: 500 });
    const down = await u.confirm(paymentId).expect(502);
    assert.equal(down.body.error.message, "Couldn't check your payment. Your money is safe — try again.");
  });

  await t.test('the return page tells the user to go back to FitSync', async () => {
    const ok = await request(app).get('/api/v1/pro/return?payment=1&result=success').expect(200);
    assert.match(ok.headers['content-type'], /text\/html/);
    assert.match(ok.text, /Payment received/);
    const no = await request(app).get('/api/v1/pro/return?payment=1&result=cancel').expect(200);
    assert.match(no.text, /Payment not completed/);
  });

  await t.test('the stub page exists only in stub mode', async () => {
    const u = await freshUser();
    const { checkoutUrl } = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    const page = await request(app).get(new URL(checkoutUrl).pathname).expect(200);
    assert.match(page.text, /FitSync Pro — 1 month/);
    assert.match(page.text, /₱249/);
    assert.match(page.text, /value="authorize"/);
    assert.match(page.text, /value="fail"/);
    await request(app).get('/api/v1/pro/stub-checkout/stub_unknown').expect(404);

    const fake = { mode: 'test', async createCheckout() { return { sessionId: 'cs_x', checkoutUrl: 'x' }; }, async getCheckout() { return { paid: false }; } };
    await request(buildTestApp({ pool, payments: fake })).get(new URL(checkoutUrl).pathname).expect(404);
  });

  // On the phone (http://192.168.x.x) or the emulator (http://10.0.2.2) the
  // browser would turn the form's POST into https:// and it would fail.
  await t.test("the stub page's policy does not upgrade its form to https", async () => {
    const u = await freshUser();
    const { checkoutUrl } = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    const page = await request(app).get(new URL(checkoutUrl).pathname).expect(200);
    const csp = page.headers['content-security-policy'];
    assert.ok(csp, 'the stub page keeps a content-security-policy');
    assert.doesNotMatch(csp, /upgrade-insecure-requests/);
    assert.match(csp, /form-action 'self'/);
    const back = await stubClick(checkoutUrl, 'fail').expect(303);
    assert.doesNotMatch(back.headers['content-security-policy'] ?? '', /upgrade-insecure-requests/);
    const ret = await request(app).get('/api/v1/pro/return?payment=1&result=success').expect(200);
    assert.match(ret.headers['content-security-policy'], /upgrade-insecure-requests/);
  });

  await t.test('a paid attempt the app lost track of is finished when the app next asks for its status', async () => {
    const u = await freshUser();
    const { checkoutUrl } = (await u.checkout({ plan: 'monthly' }).expect(201)).body.data;
    await stubClick(checkoutUrl, 'authorize').expect(303);
    // No confirm: the screen was closed, or the app killed, before it asked.
    const res = await u.status().expect(200);
    assert.equal(res.body.data.pro, true);
    assert.equal(res.body.data.source, 'paid');
    assert.equal(res.body.data.plan, 'monthly');
    await u.status().expect(200);
    assert.equal((await subsOf(u.userId)).length, 1, 'asking again adds nothing');
  });

  await t.test('checking left-behind attempts never breaks the status', async () => {
    let answer = new PaymentsError('PAYMENTS_UNAVAILABLE', { status: 500 });
    const fake = {
      mode: 'test',
      async createCheckout() { return { sessionId: `cs_s5_${Date.now()}_${Math.random()}`, checkoutUrl: 'https://checkout.paymongo.com/x' }; },
      async getCheckout() { if (answer instanceof Error) throw answer; return answer; },
    };
    const pm = buildTestApp({ pool, payments: fake });
    const u = await freshUser(pm);
    await u.checkout({ plan: 'monthly' }).expect(201);
    assert.equal((await u.status().expect(200)).body.data.pro, false, 'PayMongo down: the status still answers');
    answer = { paid: true, amountCentavos: 100, currency: 'PHP', method: 'card' };
    assert.equal((await u.status().expect(200)).body.data.pro, false, 'a paid amount that is not our price is not Pro');
    const [rows] = await pool.query('SELECT status FROM pro_payments WHERE user_id = ?', [u.userId]);
    assert.deepEqual(rows.map((r) => r.status), ['pending']);
  });

  await t.test('only the newest 3 attempts of the last day are checked', async () => {
    let calls = 0;
    const fake = {
      mode: 'test',
      async createCheckout() { return { sessionId: `cs_s5n_${Date.now()}_${Math.random()}`, checkoutUrl: 'https://checkout.paymongo.com/x' }; },
      async getCheckout() { calls += 1; return { paid: false }; },
    };
    const pm = buildTestApp({ pool, payments: fake });
    const u = await freshUser(pm);
    for (let i = 0; i < 4; i += 1) await u.checkout({ plan: 'annual' }).expect(201);
    calls = 0;
    await u.status().expect(200);
    assert.equal(calls, 3);
    await pool.query('UPDATE pro_payments SET created_at = NOW() - INTERVAL 25 HOUR WHERE user_id = ?', [u.userId]);
    calls = 0;
    await u.status().expect(200);
    assert.equal(calls, 0, 'attempts older than a day are left alone');
  });
});
