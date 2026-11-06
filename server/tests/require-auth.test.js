'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const jwt = require('jsonwebtoken');
const { signToken } = require('../src/lib/tokens');
const { setTokenCutoff } = require('../src/db/users');

const SECRET = 'test-secret-value-at-least-32-chars';
/// A token for [userId] issued at [iat] (whole seconds since the epoch).
const tokenIssuedAt = (userId, iat) =>
  jwt.sign({ iat }, SECRET, { subject: String(userId), expiresIn: '1h' });

test('requireAuth', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const cases = [
    ['no header at all', null],
    ['a bare token with no scheme', 'abc.def.ghi'],
    ['the wrong scheme', 'Basic abc'],
    ['a token signed with another secret', `Bearer ${signToken(1, { secret: 'other-secret-value', expiresIn: '1h' })}`],
  ];

  for (const [label, header] of cases) {
    await t.test(`rejects ${label}`, async () => {
      const req = request(app).get('/api/v1/auth/me');
      if (header) req.set('Authorization', header);
      const res = await req.expect(401);
      assert.equal(res.body.error.code, 'UNAUTHENTICATED');
    });
  }

  await t.test('rejects a token whose user no longer exists', async () => {
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${signToken(999999, { secret: 'test-secret-value-at-least-32-chars', expiresIn: '1h' })}`)
      .expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  // A password change or reset sets users.tokens_valid_after; every token
  // issued before it (whole seconds) is signed out, every one after works.
  await t.test('rejects a token issued before the cutoff, accepts one issued at or after it', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('cut@b.com', 'x', 'C')",
    );
    const now = Math.floor(Date.now() / 1000);
    const me = (token) => request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`);

    // No cutoff yet: an old token still works.
    await me(tokenIssuedAt(u.insertId, now - 60)).expect(200);

    await setTokenCutoff(pool, u.insertId, now - 30);
    const before = await me(tokenIssuedAt(u.insertId, now - 31)).expect(401);
    assert.equal(before.body.error.code, 'UNAUTHENTICATED');
    assert.equal(before.body.error.message, 'Sign in again to continue.');
    await me(tokenIssuedAt(u.insertId, now - 30)).expect(200);
    await me(tokenIssuedAt(u.insertId, now - 29)).expect(200);
  });

  await t.test('the exercise catalogue now requires a token', async () => {
    const res = await request(app).get('/api/v1/exercises').expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });
});
