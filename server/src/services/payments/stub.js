'use strict';

/// Stands in for PayMongo with no network (PAYMONGO_MODE=stub, the default,
/// and every test). Its "checkout page" is FitSync's own
/// /api/v1/pro/stub-checkout/<id>, whose Authorize and Fail buttons call
/// complete() the way PayMongo's test page answers. Sessions live in
/// memory: a restart forgets them, and an unpaid attempt simply stays pending.
function create() {
  const sessions = new Map();
  let seq = 0;

  async function createCheckout({ referenceNumber, name, amountCentavos, successUrl, cancelUrl, pageBase }) {
    seq += 1;
    const sessionId = `stub_${referenceNumber}_${seq}`;
    sessions.set(sessionId, { name, amountCentavos, successUrl, cancelUrl, paid: false });
    return { sessionId, checkoutUrl: `${pageBase}/api/v1/pro/stub-checkout/${sessionId}` };
  }

  async function getCheckout(sessionId) {
    const s = sessions.get(sessionId);
    return s?.paid ? { paid: true, amountCentavos: s.amountCentavos, currency: 'PHP', method: 'gcash' } : { paid: false };
  }

  /// What the stub page shows; null for an unknown session.
  function session(sessionId) {
    const s = sessions.get(sessionId);
    return s ? { name: s.name, amountCentavos: s.amountCentavos } : null;
  }

  /// The page's buttons: 'authorize' marks the session paid; anything else
  /// leaves it unpaid. Returns where PayMongo would send the browser next,
  /// or null for an unknown session.
  function complete(sessionId, action) {
    const s = sessions.get(sessionId);
    if (!s) return null;
    if (action === 'authorize') {
      s.paid = true;
      return s.successUrl;
    }
    return s.cancelUrl;
  }

  return { mode: 'stub', createCheckout, getCheckout, session, complete };
}

module.exports = { create };
