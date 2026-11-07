'use strict';

// Money per Manila month ('YYYY-MM'), for the admin overview and Revenue.
// Both answer a Map with an entry for every month asked for.
//
// Until its table exists proRevenueByMonth is zeros: Pro payment copies
// arrive with 047 (revenue_payments.paid_on), and that task fills it in.

/// Pro payments (gross pesos) by the Manila month they were paid.
async function proRevenueByMonth(_pool, months) {
  return new Map(months.map((m) => [m, 0]));
}

/// Ad amounts (pesos) by the Manila month the ad starts (046's starts_on, a
/// Manila day). A paused ad still counts: its amount was paid.
async function adRevenueByMonth(pool, months) {
  const totals = new Map(months.map((m) => [m, 0]));
  if (months.length === 0) return totals;
  const [rows] = await pool.query(
    `SELECT DATE_FORMAT(starts_on, '%Y-%m') AS month, SUM(amount_php) AS total
       FROM advertisements
      WHERE DATE_FORMAT(starts_on, '%Y-%m') IN (?)
      GROUP BY month`,
    [months],
  );
  // SUM of a DECIMAL arrives as a string.
  for (const r of rows) totals.set(r.month, Math.round(Number(r.total) * 100) / 100);
  return totals;
}

module.exports = { proRevenueByMonth, adRevenueByMonth };
