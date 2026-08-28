'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { signToken, verifyToken } = require('../src/lib/tokens');

const cfg = { secret: 'test-secret-value-at-least-32-chars', expiresIn: '30d' };

test('tokens', async (t) => {
  await t.test('round-trips a user id', () => {
    const token = signToken(7, cfg);
    assert.equal(verifyToken(token, cfg).userId, 7);
  });

  await t.test('rejects a token signed with a different secret', () => {
    const forged = jwt.sign({ sub: '7' }, 'not-the-real-secret');
    assert.throws(() => verifyToken(forged, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });

  await t.test('rejects an expired token', () => {
    const expired = jwt.sign({ sub: '7' }, cfg.secret, { expiresIn: '-1s' });
    assert.throws(() => verifyToken(expired, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });

  await t.test('rejects garbage', () => {
    assert.throws(() => verifyToken('not-a-token', cfg), (err) => err.code === 'UNAUTHENTICATED');
  });
});
