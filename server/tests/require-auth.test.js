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
const { replacePasswordAndSignOut, findUserById } = require('../src/db/users');

const SECRET = 'test-secret-value-at-least-32-chars';
const JWT = { secret: SECRET, expiresIn: '1h' };
/// A token for [userId] issued at [iat] (whole seconds since the epoch), with
/// no generation claim -- as every token signed before generations existed.
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

  // A password change or reset moves the account to a new token generation
  // (db/users.js replacePasswordAndSignOut); only tokens carrying the current
  // one work. Equality, not a time: no same-second window, and no race with
  // a login that read the old password before the change landed.
  await t.test('accepts only tokens of the current generation', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('cut@b.com', 'x', 'C')",
    );
    const me = (token) => request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`);
    const tokenOf = (generation) => signToken(u.insertId, JWT, generation);

    // Generation 0 until a password changes; a token with no claim is 0 too.
    await me(tokenOf(0)).expect(200);
    await me(tokenIssuedAt(u.insertId, Math.floor(Date.now() / 1000))).expect(200);

    const generation = await replacePasswordAndSignOut(pool, u.insertId, 'y');
    assert.equal(generation, 1);
    const before = await me(tokenOf(0)).expect(401);
    assert.equal(before.body.error.code, 'UNAUTHENTICATED');
    assert.equal(before.body.error.message, 'Sign in again to continue.');
    // Issued this very second, but from the old generation: still signed out.
    await me(tokenIssuedAt(u.insertId, Math.floor(Date.now() / 1000))).expect(401);
    await me(tokenOf(1)).expect(200);
    await me(tokenOf(2)).expect(401);
  });

  // The race the generation closes: login reads the row (old hash, old
  // generation), spends its bcrypt time, and signs. A change landing in
  // between must not leave that token alive, however late it is signed.
  await t.test('a token signed from a row read before a password change is signed out', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('race@b.com', 'x', 'C')",
    );
    const readBeforeChange = await findUserById(pool, u.insertId);
    await replacePasswordAndSignOut(pool, u.insertId, 'y');
    const late = signToken(u.insertId, JWT, readBeforeChange.token_version);
    const res = await request(app).get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${late}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('a password change writes the hash and the new generation together', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('both@b.com', 'x', 'C')",
    );
    assert.equal(await replacePasswordAndSignOut(pool, u.insertId, 'h1'), 1);
    assert.equal(await replacePasswordAndSignOut(pool, u.insertId, 'h2'), 2);
    const row = await findUserById(pool, u.insertId);
    assert.equal(row.password_hash, 'h2');
    assert.equal(row.token_version, 2);
  });

  await t.test('the exercise catalogue now requires a token', async () => {
    const res = await request(app).get('/api/v1/exercises').expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });
});
