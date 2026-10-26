'use strict';

/// SQL that is true when the users row named [alias] is Pro: granted by hand
/// (users.is_premium, `npm run pro:grant`) or a paid period that has not
/// ended. Every place that decides "is this user Pro" reads it, so a period's
/// end needs no timer -- the next request simply reads false.
function isProSql(alias) {
  return `(${alias}.is_premium = 1 OR EXISTS (
    SELECT 1 FROM subscriptions s
     WHERE s.user_id = ${alias}.user_id AND s.status = 'active' AND s.expires_at > NOW()))`;
}

/// A paid period this close to its end shows "Pro ends on …" in the app.
const ENDS_SOON_SECONDS = 3 * 24 * 60 * 60;

/// How the user is Pro, for the Pro screen: granted (no end), paid until when
/// (with the plan and payment method of the period that ends last), or not
/// at all. Times come from the database's clock -- the same one that ends the
/// period. null for a missing user.
async function proStatus(pool, userId) {
  const [[row]] = await pool.query(
    `SELECT u.is_premium AS granted, UNIX_TIMESTAMP(NOW()) AS now_epoch,
            (SELECT UNIX_TIMESTAMP(MAX(s.expires_at)) FROM subscriptions s
              WHERE s.user_id = u.user_id AND s.status = 'active' AND s.expires_at > NOW()) AS until_epoch
       FROM users u WHERE u.user_id = ?`,
    [userId],
  );
  if (!row) return null;
  if (row.granted) return { pro: true, source: 'granted', until: null, plan: null, method: null, endsSoon: false };
  if (row.until_epoch == null) return { pro: false, source: null, until: null, plan: null, method: null, endsSoon: false };
  const [[latest]] = await pool.query(
    `SELECT s.plan, p.method FROM subscriptions s
       LEFT JOIN pro_payments p ON p.subscription_id = s.subscription_id
      WHERE s.user_id = ? AND s.status = 'active' AND s.expires_at > NOW()
      ORDER BY s.expires_at DESC, s.subscription_id DESC LIMIT 1`,
    [userId],
  );
  const until = Number(row.until_epoch);
  return {
    pro: true,
    source: 'paid',
    until: new Date(until * 1000).toISOString(),
    plan: latest?.plan ?? null,
    method: latest?.method ?? null,
    endsSoon: until - Number(row.now_epoch) <= ENDS_SOON_SECONDS,
  };
}

/// A pending payment attempt at [amountPhp] (the server's price). Returns its id.
async function createPayment(pool, { userId, plan, amountPhp }) {
  const [res] = await pool.query(
    'INSERT INTO pro_payments (user_id, plan, amount_php) VALUES (?, ?, ?)', [userId, plan, amountPhp],
  );
  return res.insertId;
}

/// Records which PayMongo checkout session (or stub session) belongs to the payment.
async function setCheckoutSession(pool, paymentId, sessionId) {
  await pool.query('UPDATE pro_payments SET checkout_session_id = ? WHERE payment_id = ?', [sessionId, paymentId]);
}

/// The caller's payment, or null when it is missing or another user's.
async function findPayment(pool, userId, paymentId) {
  const [[r]] = await pool.query(
    `SELECT payment_id, user_id, plan, amount_php, checkout_session_id, status, method, subscription_id
       FROM pro_payments WHERE payment_id = ? AND user_id = ?`,
    [paymentId, userId],
  );
  if (!r) return null;
  return {
    paymentId: r.payment_id,
    userId: r.user_id,
    plan: r.plan,
    amountPhp: Number(r.amount_php),
    sessionId: r.checkout_session_id,
    status: r.status,
    method: r.method,
    subscriptionId: r.subscription_id,
  };
}

/// Marks the payment paid and adds the period it bought, in one transaction.
/// The period starts when the user's current one ends (or now), so paying
/// early loses no days; [months] is 1 or 12. Idempotent: a payment already
/// paid adds nothing ({ added: false }). null when the payment is missing or
/// another user's.
async function completePayment(pool, { userId, paymentId, months, method }) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // One user's confirmations run one at a time, so two can't both read the
    // same end date and add overlapping periods.
    await conn.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);
    const [[p]] = await conn.query(
      'SELECT status, plan, amount_php, subscription_id FROM pro_payments WHERE payment_id = ? AND user_id = ? FOR UPDATE',
      [paymentId, userId],
    );
    if (!p) {
      await conn.rollback();
      return null;
    }
    if (p.status === 'paid') {
      await conn.commit();
      return { subscriptionId: p.subscription_id, added: false };
    }
    const [sub] = await conn.query(
      `INSERT INTO subscriptions (user_id, plan, price_php, status, started_at, expires_at)
       SELECT ?, ?, ?, 'active', b.start, DATE_ADD(b.start, INTERVAL ? MONTH)
         FROM (SELECT GREATEST(NOW(), COALESCE(MAX(expires_at), NOW())) AS start
                 FROM subscriptions WHERE user_id = ? AND status = 'active') b`,
      [userId, p.plan, p.amount_php, months, userId],
    );
    await conn.query(
      "UPDATE pro_payments SET status = 'paid', method = ?, paid_at = NOW(), subscription_id = ? WHERE payment_id = ?",
      [method, sub.insertId, paymentId],
    );
    await conn.commit();
    return { subscriptionId: sub.insertId, added: true };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { isProSql, proStatus, createPayment, setCheckoutSession, findPayment, completePayment };
