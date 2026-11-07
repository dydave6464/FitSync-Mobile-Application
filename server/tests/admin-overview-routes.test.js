'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { manilaDay } = require('../src/lib/manila-day');
const { previousMonth } = require('../src/db/admin-stats');
const { adRevenueByMonth, proRevenueByMonth } = require('../src/db/revenue');

test('GET /admin/overview', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth } = await createTestAdmin(pool);
  const overview = async () => (await request(app).get('/api/v1/admin/overview').set(auth).expect(200)).body.data;

  let seq = 0;
  // A trainee row; createdDaysAgo dates created_at that many Manila days back.
  const trainee = async ({ createdDaysAgo = 0, premium = 0 } = {}) => {
    seq += 1;
    const [r] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, is_premium, created_at)
       VALUES (?, 'x', ?, ?, NOW() - INTERVAL ? DAY)`,
      [`t${seq}@example.com`, `Trainee ${seq}`, premium, createdDaysAgo],
    );
    return r.insertId;
  };
  const meal = (userId, day) => pool.query(
    `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
     VALUES (?, 'Rice', 'lunch', 200, 'manual', ?)`, [userId, day],
  );
  const weighIn = (userId, day) => pool.query(
    'INSERT INTO body_weight_logs (user_id, weight_kg, log_date) VALUES (?, 70, ?)', [userId, day],
  );
  const workout = (userId, day) => pool.query(
    'INSERT INTO workout_sessions (user_id, session_date) VALUES (?, ?)', [userId, day],
  );
  const checkIn = (userId, day) => pool.query(
    `INSERT INTO morning_checkins (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
     VALUES (?, ?, 'good', 'none', 'high', 'low')`, [userId, day],
  );
  const steps = (userId, day) => pool.query(
    'INSERT INTO activity_logs (user_id, log_date, steps) VALUES (?, ?, 1000)', [userId, day],
  );

  await t.test('a trainee token is refused', async () => {
    const id = await trainee();
    const token = signToken(id, { secret: 'test-secret-value-at-least-32-chars', expiresIn: '30d' });
    const res = await request(app).get('/api/v1/admin/overview')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('active users: any dated row in the last 30 Manila days, against the 30 before', async () => {
    const today = await trainee();
    await meal(today, manilaDay(0));
    await weighIn(today, manilaDay(0)); // two rows on one day: still one trainee
    const edge = await trainee();
    await weighIn(edge, manilaDay(29));
    const previous = await trainee();
    await workout(previous, manilaDay(30));
    const neither = await trainee();
    await checkIn(neither, manilaDay(60));
    const future = await trainee();
    await workout(future, manilaDay(-3)); // a planned day, not activity yet

    assert.deepEqual((await overview()).activeUsers, { count: 2, previousCount: 1 });

    const both = await trainee();
    await steps(both, manilaDay(5));
    await checkIn(both, manilaDay(59));
    assert.deepEqual((await overview()).activeUsers, { count: 3, previousCount: 2 });
  });

  await t.test('Pro members: granted or a paid period running', async () => {
    await trainee({ premium: 1 });
    const paid = await trainee();
    await pool.query(
      `INSERT INTO subscriptions (user_id, plan, price_php, status, expires_at)
       VALUES (?, 'monthly', 249, 'active', NOW() + INTERVAL 10 DAY)`, [paid],
    );
    const expired = await trainee();
    await pool.query(
      `INSERT INTO subscriptions (user_id, plan, price_php, status, started_at, expires_at)
       VALUES (?, 'monthly', 249, 'active', NOW() - INTERVAL 40 DAY, NOW() - INTERVAL 10 DAY)`, [expired],
    );
    assert.equal((await overview()).proMembers, 2);
  });

  await t.test('sign-ups: one entry per Manila day for the last 30, oldest first, zeros included', async () => {
    await trainee({ createdDaysAgo: 10 });
    await trainee({ createdDaysAgo: 29 });
    await trainee({ createdDaysAgo: 30 }); // outside the window
    const [[{ now }]] = await pool.query(
      'SELECT COUNT(*) AS now FROM users WHERE DATE(created_at) = CURDATE()',
    );

    const { signups } = await overview();
    assert.equal(signups.days.length, 30);
    assert.equal(signups.days[0].date, manilaDay(29));
    assert.equal(signups.days[29].date, manilaDay(0));
    assert.deepEqual(signups.days.map((d) => d.date), Array.from({ length: 30 }, (_, i) => manilaDay(29 - i)));
    assert.equal(signups.days[29].count, Number(now));
    assert.ok(Number(now) >= 1, 'users created in this test count on today');
    assert.equal(signups.days[19].count, 1); // 10 days ago
    assert.equal(signups.days[0].count, 1); // 29 days ago
    assert.equal(signups.days[1].count, 0);
    assert.equal(signups.total, signups.days.reduce((s, d) => s + d.count, 0));
    assert.equal(signups.total, Number(now) + 2);
  });

  await t.test('the whole body: today, and revenue at zero until payments and ads are recorded', async () => {
    const data = await overview();
    assert.deepEqual(Object.keys(data).sort(),
      ['activeUsers', 'adRevenue', 'proMembers', 'proRevenue', 'signups', 'today']);
    assert.equal(data.today, manilaDay());
    assert.deepEqual(data.proRevenue, { thisMonthPhp: 0, lastMonthPhp: 0 });
    assert.deepEqual(data.adRevenue, { thisMonthPhp: 0, lastMonthPhp: 0 });
  });

  await t.test('ad revenue: each ad\'s amount in the Manila month it starts', async () => {
    const thisMonth = manilaDay().slice(0, 7);
    const lastMonth = previousMonth(thisMonth);
    const ad = (startsOn, endsOn, amount, active = 1) => pool.query(
      `INSERT INTO advertisements (title, image_url, advertiser, amount_php, starts_on, ends_on, is_active)
       VALUES ('Ad', 'ads/a.jpg', 'Co', ?, ?, ?, ?)`, [amount, startsOn, endsOn, active],
    );
    await ad(`${thisMonth}-01`, `${thisMonth}-28`, 700);
    // Paused or not, an ad's amount was paid: it still counts.
    await ad(`${thisMonth}-02`, `${thisMonth}-03`, 500, 0);
    // Starts last month, runs into this one: last month's.
    await ad(`${lastMonth}-28`, `${thisMonth}-05`, 500);
    // Two months back: in neither.
    await ad(`${previousMonth(lastMonth)}-15`, `${previousMonth(lastMonth)}-20`, 999);
    const data = await overview();
    assert.deepEqual(data.adRevenue, { thisMonthPhp: 1200, lastMonthPhp: 500 });
  });

  await t.test('Pro revenue: each paid payment in the Manila month it was paid', async () => {
    const thisMonth = manilaDay().slice(0, 7);
    const lastMonth = previousMonth(thisMonth);
    const copy = (paymentId, plan, amount, paidOn) => pool.query(
      'INSERT INTO revenue_payments (payment_id, plan, amount_php, method, paid_on) VALUES (?, ?, ?, NULL, ?)',
      [paymentId, plan, amount, paidOn],
    );
    await copy(1, 'monthly', 249, `${thisMonth}-01`);
    await copy(2, 'annual', 1788, `${lastMonth}-28`);
    await copy(3, 'annual', 1788, `${previousMonth(lastMonth)}-28`); // in neither
    const data = await overview();
    assert.deepEqual(data.proRevenue, { thisMonthPhp: 249, lastMonthPhp: 1788 });
  });

  await t.test('proRevenueByMonth answers every month asked for, cents kept', async () => {
    await pool.query(
      `INSERT INTO revenue_payments (payment_id, plan, amount_php, method, paid_on)
       VALUES (10, 'monthly', 10.25, NULL, '2025-03-01'), (11, 'monthly', 0.5, 'card', '2025-03-31')`,
    );
    const got = await proRevenueByMonth(pool, ['2025-02', '2025-03']);
    assert.deepEqual([...got], [['2025-02', 0], ['2025-03', 10.75]]);
  });

  await t.test('adRevenueByMonth answers every month asked for, cents kept', async () => {
    await pool.query(
      `INSERT INTO advertisements (title, image_url, advertiser, amount_php, starts_on, ends_on)
       VALUES ('Ad', 'ads/b.jpg', 'Co', 10.25, '2025-03-04', '2025-03-05'),
              ('Ad', 'ads/c.jpg', 'Co', 0.5, '2025-03-31', '2025-04-05')`,
    );
    const got = await adRevenueByMonth(pool, ['2025-02', '2025-03']);
    assert.deepEqual([...got], [['2025-02', 0], ['2025-03', 10.75]]);
  });
});
