'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { manilaDay } = require('../src/lib/manila-day');

const ROW_KEYS = ['email', 'fullName', 'id', 'isPro', 'joinedOn', 'lastActiveOn', 'suspended'];
const DETAIL_KEYS = [
  'email', 'emailVerified', 'fullName', 'id', 'joinedOn', 'lastActiveOn', 'pro', 'signInMethods', 'suspendedAt',
];

test('admin users endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth } = await createTestAdmin(pool);
  const get = (path) => request(app).get(`/api/v1/admin${path}`).set(auth);
  const list = async (query = '') => (await get(`/users${query}`).expect(200)).body.data;

  // createdDaysAgo spaces the rows out so "newest first" has one answer.
  const trainee = async ({
    email, fullName, createdDaysAgo = 0, password = 'x', premium = 0, verified = 0, suspended = false,
  }) => {
    const [r] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, is_premium, email_verified, suspended_at, created_at)
       VALUES (?, ?, ?, ?, ?, IF(?, NOW(), NULL), NOW() - INTERVAL ? DAY)`,
      [email, password, fullName, premium, verified, suspended, createdDaysAgo],
    );
    return r.insertId;
  };
  const linkGoogle = (userId, subject) => pool.query(
    "INSERT INTO user_identities (user_id, provider, provider_subject) VALUES (?, 'google', ?)", [userId, subject],
  );

  // Oldest first here; the list answers newest first.
  const maria = await trainee({ email: 'maria@example.com', fullName: 'Maria Santos', createdDaysAgo: 40, premium: 1 });
  const juan = await trainee({ email: 'juan@example.com', fullName: 'Juan Dela Cruz', createdDaysAgo: 30, verified: 1 });
  const percent = await trainee({ email: 'promo@example.com', fullName: 'Deal 50% Off', createdDaysAgo: 20 });
  const susi = await trainee({ email: 'susi@example.com', fullName: 'Susi Reyes', createdDaysAgo: 10, suspended: true });
  const googleOnly = await trainee({
    email: 'gina@gmail.com', fullName: 'Gina Google', createdDaysAgo: 5, password: null, verified: 1,
  });
  await linkGoogle(googleOnly, 'google-sub-gina');
  const paid = await trainee({ email: 'paolo@example.com', fullName: 'Paolo Paid', createdDaysAgo: 1 });
  await pool.query(
    `INSERT INTO subscriptions (user_id, plan, price_php, status, expires_at)
     VALUES (?, 'monthly', 249, 'active', '2037-01-01 00:00:00')`, [paid],
  );

  await pool.query(
    `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
     VALUES (?, 'Rice', 'lunch', 200, 'manual', ?), (?, 'Rice', 'lunch', 200, 'manual', ?)`,
    [juan, manilaDay(3), juan, manilaDay(8)],
  );
  // A planned workout ahead of today is not activity.
  await pool.query('INSERT INTO workout_sessions (user_id, session_date) VALUES (?, ?)', [juan, manilaDay(-2)]);

  await t.test('a trainee token is refused', async () => {
    const token = signToken(juan, TEST_JWT);
    const res = await request(app).get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('newest sign-ups first, with paging defaults and the filtered total', async () => {
    const data = await list();
    assert.deepEqual(data.users.map((u) => u.id), [paid, googleOnly, susi, percent, juan, maria]);
    assert.equal(data.page, 1);
    assert.equal(data.limit, 30);
    assert.equal(data.total, 6);
  });

  await t.test('page and limit pick a slice; total still counts them all', async () => {
    const data = await list('?page=2&limit=4');
    assert.deepEqual(data.users.map((u) => u.id), [juan, maria]);
    assert.deepEqual([data.page, data.limit, data.total], [2, 4, 6]);
    assert.equal((await list('?limit=50')).limit, 50);
  });

  await t.test('limit over 50 and a bad page are 400 INVALID_QUERY_PARAM', async () => {
    const res = await get('/users?limit=51').expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    assert.equal((await get('/users?page=0').expect(400)).body.error.code, 'INVALID_QUERY_PARAM');
  });

  await t.test('q matches name or email, ignoring case', async () => {
    assert.deepEqual((await list('?q=JUAN')).users.map((u) => u.id), [juan]);
    assert.deepEqual((await list('?q=gmail')).users.map((u) => u.id), [googleOnly]);
    const reyes = await list('?q=%20reyes%20');
    assert.deepEqual(reyes.users.map((u) => u.id), [susi]);
    assert.equal(reyes.total, 1);
  });

  await t.test("q's LIKE wildcards are matched literally", async () => {
    assert.deepEqual((await list('?q=50%25')).users.map((u) => u.id), [percent]);
    assert.deepEqual((await list('?q=%25')).users.map((u) => u.id), [percent]);
    assert.deepEqual((await list('?q=_')).users, []);
    assert.deepEqual((await list('?q=%5C')).users, []);
  });

  await t.test('filter=pro: granted or a paid period running', async () => {
    const data = await list('?filter=pro');
    assert.deepEqual(data.users.map((u) => u.id), [paid, maria]);
    assert.equal(data.total, 2);
  });

  await t.test('filter=suspended and filter=all', async () => {
    assert.deepEqual((await list('?filter=suspended')).users.map((u) => u.id), [susi]);
    assert.equal((await list('?filter=all')).total, 6);
  });

  await t.test('q and filter together', async () => {
    assert.deepEqual((await list('?filter=pro&q=maria')).users.map((u) => u.id), [maria]);
    assert.equal((await list('?filter=suspended&q=maria')).total, 0);
  });

  await t.test('an unknown filter is 400 INVALID_ADMIN_FIELD', async () => {
    const res = await get('/users?filter=nope').expect(400);
    assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD');
    assert.deepEqual(res.body.error.details, [{ field: 'filter' }]);
  });

  await t.test('a repeated q is 400 INVALID_ADMIN_FIELD', async () => {
    const res = await get('/users?q=a&q=b').expect(400);
    assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD');
    assert.deepEqual(res.body.error.details, [{ field: 'q' }]);
  });

  await t.test('a row is exactly the account summary', async () => {
    const { users } = await list();
    for (const u of users) assert.deepEqual(Object.keys(u).sort(), ROW_KEYS);
    const [[{ joined }]] = await pool.query(
      "SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS joined FROM users WHERE user_id = ?", [juan],
    );
    assert.deepEqual(users.find((u) => u.id === juan), {
      id: juan,
      fullName: 'Juan Dela Cruz',
      email: 'juan@example.com',
      isPro: false,
      suspended: false,
      lastActiveOn: manilaDay(3),
      joinedOn: joined,
    });
    assert.equal(joined, manilaDay(30));
    const byId = new Map(users.map((u) => [u.id, u]));
    assert.equal(byId.get(maria).isPro, true);
    assert.equal(byId.get(paid).isPro, true);
    assert.equal(byId.get(susi).suspended, true);
    assert.equal(byId.get(maria).lastActiveOn, null);
  });

  await t.test('detail: account info only, password trainee', async () => {
    const res = await get(`/users/${juan}`).expect(200);
    const { user } = res.body.data;
    assert.deepEqual(Object.keys(res.body.data), ['user']);
    assert.deepEqual(Object.keys(user).sort(), DETAIL_KEYS);
    assert.deepEqual(user, {
      id: juan,
      fullName: 'Juan Dela Cruz',
      email: 'juan@example.com',
      joinedOn: manilaDay(30),
      emailVerified: true,
      signInMethods: ['password'],
      lastActiveOn: manilaDay(3),
      pro: { isPro: false, source: null, until: null },
      suspendedAt: null,
    });
  });

  await t.test('detail: sign-in methods come from the password and the Google link', async () => {
    assert.deepEqual((await get(`/users/${googleOnly}`).expect(200)).body.data.user.signInMethods, ['google']);
    await linkGoogle(juan, 'google-sub-juan');
    assert.deepEqual((await get(`/users/${juan}`).expect(200)).body.data.user.signInMethods, ['password', 'google']);
  });

  await t.test('detail: the Pro line is granted, paid until, or free', async () => {
    assert.deepEqual((await get(`/users/${maria}`).expect(200)).body.data.user.pro,
      { isPro: true, source: 'granted', until: null });
    const p = (await get(`/users/${paid}`).expect(200)).body.data.user.pro;
    assert.equal(p.isPro, true);
    assert.equal(p.source, 'paid');
    assert.equal(p.until, '2036-12-31T16:00:00.000Z'); // 2037-01-01 00:00 Manila
  });

  await t.test('detail: suspendedAt is an ISO time while suspended', async () => {
    const { user } = (await get(`/users/${susi}`).expect(200)).body.data;
    assert.match(user.suspendedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000Z$/);
    assert.ok(Math.abs(Date.parse(user.suspendedAt) - Date.now()) < 5 * 60 * 1000);
    assert.equal(user.emailVerified, false);
  });

  await t.test('detail: unknown and non-numeric ids are 404 USER_NOT_FOUND', async () => {
    for (const id of [999999, 'abc', '1.5']) {
      const res = await get(`/users/${id}`).expect(404);
      assert.equal(res.body.error.code, 'USER_NOT_FOUND', String(id));
      assert.equal(res.body.error.message, 'No such trainee.');
    }
  });
});
