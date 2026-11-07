'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
const { signToken, verifyToken } = require('../src/lib/tokens');
const { adminKey, signAdminToken, verifyAdminToken } = require('../src/lib/admin-tokens');

const JWT = { secret: 'test-secret-value-at-least-32-chars', expiresIn: '30d' };

const isUnauthenticated = (err) => err.status === 401 && err.code === 'UNAUTHENTICATED'
  && err.message === 'Sign in again to continue.';

test('admin tokens', async (t) => {
  await t.test('the admin key is the JWT secret under its own label', () => {
    const expected = crypto.createHmac('sha256', JWT.secret).update('fitsync-admin-token').digest();
    assert.ok(Buffer.isBuffer(adminKey(JWT.secret)));
    assert.deepEqual(adminKey(JWT.secret), expected);
    assert.throws(() => adminKey(''));
    assert.throws(() => adminKey(undefined));
  });

  await t.test('an admin token verifies to its admin id', () => {
    assert.deepEqual(verifyAdminToken(signAdminToken(7, JWT), JWT), { adminId: 7 });
  });

  await t.test('a trainee token is not an admin token', () => {
    assert.throws(() => verifyAdminToken(signToken(7, JWT, 0), JWT), isUnauthenticated);
  });

  await t.test('an admin token is not a trainee token', () => {
    assert.throws(() => verifyToken(signAdminToken(7, JWT), JWT), isUnauthenticated);
  });

  await t.test('a token signed with the admin key but without the admin role is refused', () => {
    const token = jwt.sign({ role: 'trainee' }, adminKey(JWT.secret), { subject: '7', expiresIn: '1h' });
    assert.throws(() => verifyAdminToken(token, JWT), isUnauthenticated);
  });

  await t.test('a bad subject is refused', () => {
    for (const subject of ['0', '-1', 'abc', '1.5']) {
      const token = jwt.sign({ role: 'admin' }, adminKey(JWT.secret), { subject, expiresIn: '1h' });
      assert.throws(() => verifyAdminToken(token, JWT), isUnauthenticated, subject);
    }
  });

  await t.test('an expired admin token is refused', () => {
    const token = signAdminToken(7, { ...JWT, expiresIn: '-1s' });
    assert.throws(() => verifyAdminToken(token, JWT), isUnauthenticated);
  });

  await t.test('an unsigned (alg: none) token is refused', () => {
    const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    const body = Buffer.from(JSON.stringify({ role: 'admin', sub: '7' })).toString('base64url');
    assert.throws(() => verifyAdminToken(`${header}.${body}.`, JWT), isUnauthenticated);
  });

  await t.test('garbage is refused', () => {
    assert.throws(() => verifyAdminToken('not-a-token', JWT), isUnauthenticated);
  });
});
