'use strict';
const stub = require('./stub');
const paymongoClient = require('./paymongo-client');

/// Picks how Pro is paid for, like services/vision. stub (the default): no
/// network, FitSync's own test page -- what every test runs. test: PayMongo's
/// test mode. This build never takes a live key, so it can never charge real
/// money; startup fails rather than the first payment -- in every mode, so a
/// live key left in .env is caught even while the stub is in use. [deps]
/// (fetchImpl, timeoutMs) are for the tests and can never replace the key.
function createPaymentsService(cfg = {}, deps = {}) {
  const key = cfg.secretKey;
  if (key?.startsWith('sk_live_')) {
    throw new Error('PAYMONGO_SECRET_KEY is a live key; this build takes PayMongo test keys (sk_test_...) only');
  }
  const mode = cfg.mode || 'stub';
  if (mode === 'stub') return stub.create();
  if (mode === 'test') {
    if (!key) throw new Error('PAYMONGO_SECRET_KEY is required when PAYMONGO_MODE=test');
    if (!key.startsWith('sk_test_')) throw new Error('PAYMONGO_SECRET_KEY must be a PayMongo secret test key (sk_test_...)');
    return paymongoClient.create({ ...deps, secretKey: key });
  }
  throw new Error(`Unsupported PAYMONGO_MODE: ${mode}`);
}

module.exports = { createPaymentsService };
