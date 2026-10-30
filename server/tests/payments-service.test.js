'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('../src/config');
const { createPaymentsService } = require('../src/services/payments');
const paymongo = require('../src/services/payments/paymongo-client');
const { PaymentsError } = require('../src/services/payments/errors');

const ENV = { DB_HOST: 'h', DB_PORT: '3306', DB_USER: 'u', DB_PASSWORD: 'p', DB_NAME: 'n', JWT_SECRET: 'x'.repeat(32) };
const URL_V1 = 'https://api.paymongo.com/v1/checkout_sessions';

/// A fetch that answers each call from [replies] in turn and records what it was sent.
function fakeFetch(replies) {
  const calls = [];
  const fn = async (url, opts) => {
    calls.push({ url, opts, body: opts.body ? JSON.parse(opts.body) : null });
    const r = replies[calls.length - 1];
    if (typeof r === 'function') return r(opts);
    return { ok: r.status >= 200 && r.status < 300, status: r.status, json: async () => r.json };
  };
  fn.calls = calls;
  return fn;
}
const ARGS = {
  referenceNumber: 'fitsync-7', name: 'FitSync Pro — 1 month', amountCentavos: 24900,
  successUrl: 'http://192.168.1.10:3000/api/v1/pro/return?payment=7&result=success',
  cancelUrl: 'http://192.168.1.10:3000/api/v1/pro/return?payment=7&result=cancel',
  pageBase: 'http://192.168.1.10:3000',
};
const paidSession = (type, amount = 24900) => ({ data: { id: 'cs_1', attributes: { status: 'active', payments: [
  { id: 'pay_1', attributes: { status: 'paid', amount, currency: 'PHP', source: { id: 'src_1', type } } },
] } } });

test('config: PAYMONGO_MODE defaults to the stub; the key is trimmed', () => {
  assert.deepEqual(load(ENV).payments, { mode: 'stub', secretKey: null });
  assert.deepEqual(load({ ...ENV, PAYMONGO_MODE: 'test', PAYMONGO_SECRET_KEY: ' sk_test_abc \n' }).payments, { mode: 'test', secretKey: 'sk_test_abc' });
});

test('createPaymentsService: stub by default; test mode takes only a test key', () => {
  assert.equal(createPaymentsService({}).mode, 'stub');
  assert.throws(() => createPaymentsService({ mode: 'test' }), /PAYMONGO_SECRET_KEY is required when PAYMONGO_MODE=test/);
  assert.throws(() => createPaymentsService({ mode: 'test', secretKey: 'sk_live_abc' }), /live key/);
  assert.throws(() => createPaymentsService({ mode: 'test', secretKey: 'pk_test_abc' }), /sk_test_/);
  assert.equal(createPaymentsService({ mode: 'test', secretKey: 'sk_test_abc' }).mode, 'test');
  assert.throws(() => createPaymentsService({ mode: 'live', secretKey: 'sk_test_abc' }), /Unsupported PAYMONGO_MODE: live/);
});

test('createPaymentsService: a live key stops startup in every mode, and the test hooks cannot swap the key', async () => {
  assert.throws(() => createPaymentsService({ secretKey: 'sk_live_abc' }), /live key/);
  assert.throws(() => createPaymentsService({ mode: 'stub', secretKey: 'sk_live_abc' }), /live key/);
  const fetchImpl = fakeFetch([{ status: 200, json: { data: { id: 'cs_abc', attributes: { checkout_url: 'https://checkout.paymongo.com/cs_abc' } } } }]);
  await createPaymentsService({ mode: 'test', secretKey: 'sk_test_abc' }, { secretKey: 'sk_live_xyz', fetchImpl }).createCheckout(ARGS);
  assert.equal(fetchImpl.calls[0].opts.headers.authorization, `Basic ${Buffer.from('sk_test_abc:').toString('base64')}`);
});

test('paymongo: creates a checkout for the given amount, GCash, Maya and card, coming back to us', async () => {
  const fetchImpl = fakeFetch([{ status: 200, json: { data: { id: 'cs_abc', attributes: { checkout_url: 'https://checkout.paymongo.com/cs_abc' } } } }]);
  const out = await paymongo.create({ secretKey: 'sk_test_abc', fetchImpl }).createCheckout(ARGS);
  assert.deepEqual(out, { sessionId: 'cs_abc', checkoutUrl: 'https://checkout.paymongo.com/cs_abc' });
  const { url, opts, body } = fetchImpl.calls[0];
  assert.equal(url, URL_V1);
  assert.equal(opts.method, 'POST');
  assert.equal(opts.headers.authorization, `Basic ${Buffer.from('sk_test_abc:').toString('base64')}`);
  assert.deepEqual(body.data.attributes.line_items, [{ name: 'FitSync Pro — 1 month', amount: 24900, currency: 'PHP', quantity: 1 }]);
  assert.deepEqual(body.data.attributes.payment_method_types, ['gcash', 'paymaya', 'card']);
  assert.equal(body.data.attributes.reference_number, 'fitsync-7');
  assert.equal(body.data.attributes.success_url, ARGS.successUrl);
  assert.equal(body.data.attributes.cancel_url, ARGS.cancelUrl);
});

test('paymongo: a refused or broken create is PAYMENTS_UNAVAILABLE with its status', async () => {
  for (const reply of [{ status: 401, json: { errors: [{ code: 'unauthorized' }] } }, { status: 200, json: { data: {} } }]) {
    await assert.rejects(paymongo.create({ secretKey: 'sk_test_abc', fetchImpl: fakeFetch([reply]) }).createCheckout(ARGS),
      (e) => e instanceof PaymentsError && e.code === 'PAYMENTS_UNAVAILABLE' && e.status === (reply.status === 401 ? 401 : null));
  }
  const down = fakeFetch([() => Promise.reject(new Error('ECONNRESET'))]);
  await assert.rejects(paymongo.create({ secretKey: 'sk_test_abc', fetchImpl: down }).createCheckout(ARGS),
    (e) => e.code === 'PAYMENTS_UNAVAILABLE' && e.cause?.message === 'ECONNRESET');
});

test('paymongo: reads a session as paid only when PayMongo marked a payment paid', async () => {
  const client = (reply) => paymongo.create({ secretKey: 'sk_test_abc', fetchImpl: fakeFetch([reply]) });
  assert.deepEqual(await client({ status: 200, json: { data: { id: 'cs_1', attributes: { status: 'active', payments: [] } } } }).getCheckout('cs_1'), { paid: false });
  assert.deepEqual(await client({ status: 200, json: paidSession('gcash') }).getCheckout('cs_1'),
    { paid: true, amountCentavos: 24900, currency: 'PHP', method: 'gcash' });
  assert.equal((await client({ status: 200, json: paidSession('paymaya') }).getCheckout('cs_1')).method, 'paymaya');
  assert.equal((await client({ status: 200, json: paidSession('something_new') }).getCheckout('cs_1')).method, null);
  assert.deepEqual(await client({ status: 404, json: { errors: [] } }).getCheckout('cs_gone'), { paid: false });
  await assert.rejects(client({ status: 500, json: {} }).getCheckout('cs_1'), (e) => e.code === 'PAYMENTS_UNAVAILABLE' && e.status === 500);

  const f = fakeFetch([{ status: 200, json: paidSession('card') }]);
  await paymongo.create({ secretKey: 'sk_test_abc', fetchImpl: f }).getCheckout('cs_a/b');
  assert.equal(f.calls[0].url, `${URL_V1}/cs_a%2Fb`);
  assert.equal(f.calls[0].opts.method, 'GET');
});

test('paymongo: a request that hangs is cut off', async () => {
  const slow = fakeFetch([(opts) => new Promise((_, reject) => {
    opts.signal.addEventListener('abort', () => reject(new Error('aborted')));
  })]);
  const started = Date.now();
  await assert.rejects(paymongo.create({ secretKey: 'sk_test_abc', fetchImpl: slow, timeoutMs: 20 }).getCheckout('cs_1'),
    (e) => e.code === 'PAYMENTS_UNAVAILABLE');
  assert.ok(Date.now() - started < 1000);
});

test('stub: its own page stands in for PayMongo', async () => {
  const stub = createPaymentsService({});
  const { sessionId, checkoutUrl } = await stub.createCheckout(ARGS);
  assert.match(sessionId, /^stub_fitsync-7_\d+$/);
  assert.equal(checkoutUrl, `http://192.168.1.10:3000/api/v1/pro/stub-checkout/${sessionId}`);
  assert.deepEqual(stub.session(sessionId), { name: 'FitSync Pro — 1 month', amountCentavos: 24900 });
  assert.deepEqual(await stub.getCheckout(sessionId), { paid: false });
  assert.equal(stub.complete(sessionId, 'fail'), ARGS.cancelUrl);
  assert.deepEqual(await stub.getCheckout(sessionId), { paid: false });
  assert.equal(stub.complete(sessionId, 'authorize'), ARGS.successUrl);
  assert.deepEqual(await stub.getCheckout(sessionId), { paid: true, amountCentavos: 24900, currency: 'PHP', method: 'gcash' });
  assert.equal(stub.session('stub_unknown'), null);
  assert.equal(stub.complete('stub_unknown', 'authorize'), null);
});
