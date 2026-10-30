'use strict';
const { PaymentsError } = require('./errors');

// v1, not v2: v1's reply is the whole session, and its sessions read back at
// /v1/checkout_sessions/{id} (checked with a test key on 2026-10-26; /v2
// sessions 404 at /v2).
const API = 'https://api.paymongo.com/v1/checkout_sessions';
const TIMEOUT_MS = 15000;
// PayMongo's names; the app shows them as GCash, Maya and card.
const METHODS = ['gcash', 'paymaya', 'card'];

/// PayMongo's hosted checkout, test mode. The secret key goes in the
/// Authorization header and nowhere else; card and wallet details stay on
/// PayMongo's page. [fetchImpl] and [timeoutMs] are for the tests.
function create({ secretKey, fetchImpl = fetch, timeoutMs = TIMEOUT_MS }) {
  const authorization = `Basic ${Buffer.from(`${secretKey}:`).toString('base64')}`;

  /// The parsed reply, or { notFound: true } for a 404; PaymentsError otherwise.
  async function call(url, init) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, {
        ...init,
        signal: controller.signal,
        headers: { authorization, accept: 'application/json', 'content-type': 'application/json' },
      });
      if (res.status === 404) return { notFound: true };
      if (!res.ok) throw new PaymentsError('PAYMENTS_UNAVAILABLE', { status: res.status });
      return await res.json();
    } catch (err) {
      if (err instanceof PaymentsError) throw err;
      throw new PaymentsError('PAYMENTS_UNAVAILABLE', { cause: err });
    } finally {
      clearTimeout(timer);
    }
  }

  /// [referenceNumber] ties PayMongo's session to our pro_payments row.
  async function createCheckout({ referenceNumber, name, amountCentavos, successUrl, cancelUrl }) {
    const json = await call(API, {
      method: 'POST',
      body: JSON.stringify({
        data: {
          attributes: {
            line_items: [{ name, amount: amountCentavos, currency: 'PHP', quantity: 1 }],
            payment_method_types: METHODS,
            reference_number: referenceNumber,
            success_url: successUrl,
            cancel_url: cancelUrl,
            show_line_items: true,
          },
        },
      }),
    });
    const sessionId = json?.data?.id;
    const checkoutUrl = json?.data?.attributes?.checkout_url;
    if (typeof sessionId !== 'string' || typeof checkoutUrl !== 'string') throw new PaymentsError('PAYMENTS_UNAVAILABLE');
    return { sessionId, checkoutUrl };
  }

  /// Paid only when the session holds a payment PayMongo marked 'paid' --
  /// with what was actually paid, for the route to compare with our price.
  /// A session PayMongo no longer knows reads unpaid.
  async function getCheckout(sessionId) {
    const json = await call(`${API}/${encodeURIComponent(sessionId)}`, { method: 'GET' });
    if (json?.notFound) return { paid: false };
    const payments = json?.data?.attributes?.payments;
    const paid = Array.isArray(payments) ? payments.find((p) => p?.attributes?.status === 'paid') : null;
    if (!paid) return { paid: false };
    const a = paid.attributes;
    const type = a.source?.type;
    return { paid: true, amountCentavos: a.amount, currency: a.currency, method: METHODS.includes(type) ? type : null };
  }

  return { mode: 'test', createCheckout, getCheckout };
}

module.exports = { create, METHODS };
