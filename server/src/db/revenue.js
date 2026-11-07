'use strict';
const { manilaDay } = require('../lib/manila-day');
const { listAdsForMonth } = require('./ads');

// Money per Manila month ('YYYY-MM'), for the admin overview and Revenue.
// Pro money comes from revenue_payments (047), the anonymous copies of paid
// payments, so it survives account deletion; ad money from advertisements.

const LAST_MONTHS = 6;

/// Pesos to the cent: SUM of a DECIMAL arrives as a string, and adding
/// floats can leave a stray fraction.
const pesos = (n) => Math.round(Number(n) * 100) / 100;

/// 'YYYY-MM' of the month before [ym].
function previousMonth(ym) {
  const [y, m] = ym.split('-').map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
}

/// SUM([amountColumn]) of [table] grouped by the month of [dayColumn], as a
/// Map with an entry (0 when none) for every month in [months].
async function totalsByMonth(pool, table, dayColumn, months) {
  const totals = new Map(months.map((m) => [m, 0]));
  if (months.length === 0) return totals;
  const [rows] = await pool.query(
    `SELECT DATE_FORMAT(${dayColumn}, '%Y-%m') AS month, SUM(amount_php) AS total
       FROM ${table}
      WHERE DATE_FORMAT(${dayColumn}, '%Y-%m') IN (?)
      GROUP BY month`,
    [months],
  );
  for (const r of rows) totals.set(r.month, pesos(r.total));
  return totals;
}

/// Pro payments (gross pesos) by the Manila month they were paid (047's
/// paid_on, a Manila day).
function proRevenueByMonth(pool, months) {
  return totalsByMonth(pool, 'revenue_payments', 'paid_on', months);
}

/// Ad amounts (pesos) by the Manila month the ad starts (046's starts_on, a
/// Manila day). A paused ad still counts: its amount was paid.
function adRevenueByMonth(pool, months) {
  return totalsByMonth(pool, 'advertisements', 'starts_on', months);
}

/// The month's paid Pro payments, newest day first (the newer payment first
/// on one day). name is the trainee's, or null once their account is gone:
/// the copy outlives the pro_payments row, which cascades with the user.
async function proPaymentsForMonth(pool, month) {
  const [rows] = await pool.query(
    `SELECT r.payment_id, u.full_name, r.plan, r.method, r.amount_php,
            DATE_FORMAT(r.paid_on, '%Y-%m-%d') AS paid_on
       FROM revenue_payments r
       LEFT JOIN pro_payments p ON p.payment_id = r.payment_id
       LEFT JOIN users u ON u.user_id = p.user_id
      WHERE DATE_FORMAT(r.paid_on, '%Y-%m') = ?
      ORDER BY r.paid_on DESC, r.payment_id DESC`,
    [month],
  );
  return rows.map((r) => ({
    paymentId: r.payment_id,
    name: r.full_name ?? null,
    plan: r.plan,
    method: r.method,
    amountPhp: pesos(r.amount_php),
    paidOn: r.paid_on,
  }));
}

/// The earliest month with a payment copy or an ad ('YYYY-MM'), or null.
async function firstRevenueMonth(pool) {
  const [[row]] = await pool.query(
    `SELECT DATE_FORMAT(LEAST(
              COALESCE((SELECT MIN(paid_on) FROM revenue_payments), '9999-12-31'),
              COALESCE((SELECT MIN(starts_on) FROM advertisements), '9999-12-31')), '%Y-%m') AS first`,
  );
  return row.first === '9999-12' ? null : row.first;
}

/// The admin Revenue screen for [month] ('YYYY-MM'; this Manila month when
/// null): Appendix A's GET /admin/revenue data.
async function revenueMonth(pool, month, today = manilaDay()) {
  const ym = month ?? today.slice(0, 7);
  const months = [ym];
  while (months.length < LAST_MONTHS) months.unshift(previousMonth(months[0]));

  const [proByMonth, adsByMonth, proPayments, adPayments, firstMonth] = await Promise.all([
    proRevenueByMonth(pool, months),
    adRevenueByMonth(pool, months),
    proPaymentsForMonth(pool, ym),
    listAdsForMonth(pool, ym),
    firstRevenueMonth(pool),
  ]);

  const monthTotal = (m) => pesos(proByMonth.get(m) + adsByMonth.get(m));
  return {
    month: ym,
    totalPhp: monthTotal(ym),
    previousTotalPhp: monthTotal(previousMonth(ym)),
    pro: {
      totalPhp: proByMonth.get(ym),
      monthly: proPayments.filter((p) => p.plan === 'monthly').length,
      annual: proPayments.filter((p) => p.plan === 'annual').length,
    },
    ads: { totalPhp: adsByMonth.get(ym), count: adPayments.length },
    lastSixMonths: months.map((m) => ({ month: m, proPhp: proByMonth.get(m), adsPhp: adsByMonth.get(m) })),
    proPayments,
    adPayments,
    firstMonth,
  };
}

module.exports = { previousMonth, proRevenueByMonth, adRevenueByMonth, revenueMonth };
