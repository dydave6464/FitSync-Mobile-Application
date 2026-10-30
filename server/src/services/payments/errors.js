'use strict';

/// How a payment call failed: PAYMENTS_UNAVAILABLE (PayMongo refused, broke,
/// or did not answer). [status] is PayMongo's HTTP status when it answered,
/// [cause] the original error for a timeout or network failure -- so the
/// route can log why without logging a body or a key.
class PaymentsError extends Error {
  constructor(code, { status = null, cause } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = 'PaymentsError';
    this.code = code;
    this.status = status;
  }
}

module.exports = { PaymentsError };
