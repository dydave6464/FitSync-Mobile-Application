'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { signToken } = require('../src/lib/tokens');
const { issueToken } = require('../src/lib/auth-tokens');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { createPayment } = require('../src/db/pro');
const { markEmailVerified } = require('../src/db/users');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

const JWT = { secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h' };

test('delete account from the app', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  // The default Google verifier is the stub: stub-token-juan and
  // stub-token-maria verify as two different Google accounts.
  const app = buildTestApp({ pool });

  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reset = async () => {
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
  };

  const passwordUser = async (email = 'ana@example.com', password = 's3cret-pass') => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password, fullName: 'Ana' }).expect(201);
    const { userId } = res.body.data.user;
    await markEmailVerified(pool, userId);
    return { userId, token: signToken(userId, JWT) };
  };

  const googleUser = async (idToken = 'stub-token-juan') => {
    const res = await request(app).post('/api/v1/auth/google').send({ idToken }).expect(200);
    return { userId: res.body.data.user.userId, token: res.body.data.token };
  };

  /// A row in each kind of table the account owns: profile (its health
  /// check), training, nutrition, weigh-ins, payments, sign-in identities
  /// and emailed tokens.
  const seed = async (userId) => {
    await pool.query(
      `INSERT INTO health_checks (user_id, chest_pain, dizziness, supervised_only)
       VALUES (?, 0, 0, 0)`, [userId],
    );
    await pool.query(
      "INSERT INTO workout_sessions (user_id, session_date, status) VALUES (?, CURDATE(), 'completed')",
      [userId],
    );
    await pool.query(
      `INSERT INTO meal_logs (user_id, custom_name, meal_type, calories, logged_via, log_date)
       VALUES (?, 'Rice', 'lunch', 200, 'manual', CURDATE())`, [userId],
    );
    await pool.query(
      'INSERT INTO body_weight_logs (user_id, weight_kg, log_date) VALUES (?, 70, CURDATE())',
      [userId],
    );
    await createPayment(pool, { userId, plan: 'monthly', amountPhp: 149 });
    await pool.query(
      "INSERT IGNORE INTO user_identities (user_id, provider, provider_subject) VALUES (?, 'google', ?)",
      [userId, `seeded-sub-${userId}`],
    );
    await issueToken(pool, { userId, purpose: 'verify_email' });
  };

  const REPRESENTATIVE = [
    'health_checks', 'workout_sessions', 'meal_logs', 'body_weight_logs',
    'pro_payments', 'user_identities', 'auth_tokens',
  ];
  const representativeCounts = async (userId) => {
    const counts = {};
    for (const table of REPRESENTATIVE) {
      const [[row]] = await pool.query(
        `SELECT COUNT(*) AS n FROM ${table} WHERE user_id = ?`, [userId],
      );
      counts[table] = Number(row.n);
    }
    return counts;
  };

  /// Every column anywhere that references users(user_id), and how many rows
  /// in it still point at [userId] -- the whole account, not a sample.
  const rowsAnywhere = async (userId) => {
    const [refs] = await pool.query(
      `SELECT TABLE_NAME AS t, COLUMN_NAME AS c FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE() AND REFERENCED_TABLE_NAME = 'users'
          AND REFERENCED_COLUMN_NAME = 'user_id'`,
    );
    assert.ok(refs.length >= 30, `expected the user tables, found ${refs.length}`);
    let total = 0;
    for (const { t: table, c: column } of refs) {
      const [[row]] = await pool.query(
        `SELECT COUNT(*) AS n FROM ?? WHERE ?? = ?`, [table, column, userId],
      );
      total += Number(row.n);
    }
    const [[own]] = await pool.query('SELECT COUNT(*) AS n FROM users WHERE user_id = ?', [userId]);
    return total + Number(own.n);
  };

  const del = (token, body) => {
    const req = request(app).post('/api/v1/account/delete');
    if (token) req.set('Authorization', `Bearer ${token}`);
    return body === undefined ? req : req.send(body);
  };
  const me = (token) => request(app).get('/api/v1/auth/me')
    .set('Authorization', `Bearer ${token}`);

  await t.test('a password account deletes itself and all its data with its password', async () => {
    await reset();
    const { userId, token } = await passwordUser();
    await seed(userId);
    for (const [table, n] of Object.entries(await representativeCounts(userId))) {
      assert.ok(n > 0, `seeded a row in ${table}`);
    }

    const res = await del(token, { password: 's3cret-pass' });
    assert.equal(res.status, 204);
    assert.equal(res.text, '');

    assert.deepEqual(await representativeCounts(userId), Object.fromEntries(
      REPRESENTATIVE.map((table) => [table, 0]),
    ));
    assert.equal(await rowsAnywhere(userId), 0, 'no row anywhere still belongs to the account');

    const stale = await me(token).expect(401);
    assert.equal(stale.body.error.code, 'UNAUTHENTICATED');
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email: 'ana@example.com', password: 's3cret-pass' });
    assert.equal(login.status, 401);
  });

  await t.test("another user's data is untouched", async () => {
    await reset();
    const gone = await passwordUser('gone@example.com');
    const kept = await passwordUser('kept@example.com');
    await seed(gone.userId);
    await seed(kept.userId);
    const before = await representativeCounts(kept.userId);
    const anywhereBefore = await rowsAnywhere(kept.userId);

    await del(gone.token, { password: 's3cret-pass' }).expect(204);

    assert.deepEqual(await representativeCounts(kept.userId), before);
    assert.equal(await rowsAnywhere(kept.userId), anywhereBefore);
    await me(kept.token).expect(200);
  });

  await t.test('a wrong password is WRONG_PASSWORD and deletes nothing', async () => {
    await reset();
    const { userId, token } = await passwordUser();
    await seed(userId);
    const before = await rowsAnywhere(userId);

    for (const password of ['not-my-pass', '', '   ', 'x'.repeat(200)]) {
      const res = await del(token, { password });
      assert.equal(res.status, 400, `password ${JSON.stringify(password.slice(0, 12))}`);
      assert.equal(res.body.error.code, 'WRONG_PASSWORD');
      assert.equal(res.body.error.message, "That password isn't right.");
    }

    assert.equal(await rowsAnywhere(userId), before);
    await me(token).expect(200);
  });

  await t.test('no re-confirmation is REAUTH_REQUIRED', async () => {
    await reset();
    const { token } = await passwordUser();

    for (const body of [undefined, {}, { password: null }, { password: 12345678 }, { idToken: 7 }]) {
      const res = await del(token, body);
      assert.equal(res.status, 400, `body ${JSON.stringify(body)}`);
      assert.equal(res.body.error.code, 'REAUTH_REQUIRED');
      assert.equal(res.body.error.message, "Confirm it's you to delete your account.");
    }
    await me(token).expect(200);
  });

  await t.test('the wrong kind of re-confirmation is REAUTH_REQUIRED', async () => {
    await reset();
    // A password account with no Google identity cannot confirm with Google.
    const byPassword = await passwordUser();
    const viaGoogle = await del(byPassword.token, { idToken: 'stub-token-maria' });
    assert.equal(viaGoogle.status, 400);
    assert.equal(viaGoogle.body.error.code, 'REAUTH_REQUIRED');
    await me(byPassword.token).expect(200);

    // A Google-only account has no password to confirm with.
    const byGoogle = await googleUser();
    const viaPassword = await del(byGoogle.token, { password: 'anything at all' });
    assert.equal(viaPassword.status, 400);
    assert.equal(viaPassword.body.error.code, 'REAUTH_REQUIRED');
    await me(byGoogle.token).expect(200);
  });

  await t.test('a Google-only account deletes itself with a matching Google sign-in', async () => {
    await reset();
    const { userId, token } = await googleUser('stub-token-juan');
    await seed(userId);

    await del(token, { idToken: 'stub-token-juan' }).expect(204);

    assert.equal(await rowsAnywhere(userId), 0);
    await me(token).expect(401);
  });

  await t.test('a different Google account is GOOGLE_ACCOUNT_MISMATCH and deletes nothing', async () => {
    await reset();
    const juan = await googleUser('stub-token-juan');
    // Maria's Google account is a real account here too: matching her
    // identity must not delete Juan, nor Maria.
    const maria = await googleUser('stub-token-maria');

    const res = await del(juan.token, { idToken: 'stub-token-maria' });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'GOOGLE_ACCOUNT_MISMATCH');
    assert.equal(res.body.error.message, "That Google account isn't the one this account uses.");

    await me(juan.token).expect(200);
    await me(maria.token).expect(200);
  });

  await t.test('a Google sign-in that does not verify is REAUTH_REQUIRED and deletes nothing', async () => {
    await reset();
    // The contract lists 400s only (plus 401 for the app's own session): a
    // 401 here would read as "signed out" to the app.
    const { userId, token } = await googleUser('stub-token-juan');
    await seed(userId);
    const before = await rowsAnywhere(userId);

    const res = await del(token, { idToken: 'not-a-google-token' });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'REAUTH_REQUIRED');
    assert.equal(res.body.error.message, "Confirm it's you to delete your account.");

    assert.equal(await rowsAnywhere(userId), before);
    await me(token).expect(200);
  });

  await t.test('a password account that also links Google may confirm with either', async () => {
    await reset();
    // Same address as the stub's Juan: signing in with Google links it.
    const { userId, token } = await passwordUser('juan@example.com');
    await googleUser('stub-token-juan');

    await del(token, { idToken: 'stub-token-juan' }).expect(204);
    assert.equal(await rowsAnywhere(userId), 0);
  });

  await t.test('without a sign-in it is 401 and deletes nothing', async () => {
    await reset();
    const { userId } = await passwordUser();

    const res = await del(null, { password: 's3cret-pass' });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    const [[row]] = await pool.query('SELECT COUNT(*) AS n FROM users WHERE user_id = ?', [userId]);
    assert.equal(Number(row.n), 1);
  });
});
