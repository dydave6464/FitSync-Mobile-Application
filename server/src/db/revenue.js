'use strict';

// Money per Manila month ('YYYY-MM'), for the admin overview and Revenue.
// Both answer a Map with an entry for every month asked for.
//
// Until the tables they read exist these are zeros: ad amounts arrive with
// migration 046 (advertisements.amount_php, starts_on) and Pro payment
// copies with 047 (revenue_payments.paid_on). Those tasks fill the bodies in.

/// Pro payments (gross pesos) by the Manila month they were paid.
async function proRevenueByMonth(_pool, months) {
  return new Map(months.map((m) => [m, 0]));
}

/// Ad amounts (pesos) by the Manila month the ad starts.
async function adRevenueByMonth(_pool, months) {
  return new Map(months.map((m) => [m, 0]));
}

module.exports = { proRevenueByMonth, adRevenueByMonth };
