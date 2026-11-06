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

  // requireAuth compares this with users.token_version: a password change or
  // reset moves the account to a new generation and signs out the old one.
  await t.test('round-trips the token generation', () => {
    assert.equal(verifyToken(signToken(7, cfg, 3), cfg).tokenVersion, 3);
  });

  await t.test('a token signed without a generation is generation 0', () => {
    assert.equal(verifyToken(signToken(7, cfg), cfg).tokenVersion, 0);
    // Tokens issued before generations existed carry no claim at all; they
    // belong to the generation every account starts at.
    const legacy = jwt.sign({}, cfg.secret, { subject: '7', expiresIn: '1h' });
    assert.equal(verifyToken(legacy, cfg).tokenVersion, 0);
  });

  await t.test('rejects a generation that is not a whole number of at least 0', () => {
    for (const tv of ['1', -1, 1.5, null]) {
      const token = jwt.sign({ tv }, cfg.secret, { subject: '7', expiresIn: '1h' });
      assert.throws(() => verifyToken(token, cfg), (err) => err.code === 'UNAUTHENTICATED',
        JSON.stringify(tv));
    }
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

  await t.test('indistinguishable rejection: all three paths yield identical code and message', () => {
    // The security property: bad signature, expired token, and garbage must be
    // indistinguishable to a caller. Saying which occurred tells an attacker
    // whether they had the shape right. Capture the actual errors and assert
    // they match exactly.
    let forgedError;
    let expiredError;
    let garbageError;

    try {
      verifyToken(jwt.sign({ sub: '7' }, 'not-the-real-secret'), cfg);
    } catch (err) {
      forgedError = err;
    }

    try {
      verifyToken(jwt.sign({ sub: '7' }, cfg.secret, { expiresIn: '-1s' }), cfg);
    } catch (err) {
      expiredError = err;
    }

    try {
      verifyToken('not-a-token', cfg);
    } catch (err) {
      garbageError = err;
    }

    // Assert all three have the same code and message
    assert.equal(forgedError.code, 'UNAUTHENTICATED');
    assert.equal(expiredError.code, 'UNAUTHENTICATED');
    assert.equal(garbageError.code, 'UNAUTHENTICATED');
    assert.equal(forgedError.message, expiredError.message);
    assert.equal(expiredError.message, garbageError.message);
  });

  await t.test('id validation: rejects a missing sub (validly signed but no subject)', () => {
    const noSub = jwt.sign({}, cfg.secret);
    assert.throws(() => verifyToken(noSub, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });

  await t.test('id validation: rejects a non-numeric sub', () => {
    const badSub = jwt.sign({}, cfg.secret, { subject: 'not-a-number' });
    assert.throws(() => verifyToken(badSub, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });

  await t.test('id validation: rejects sub = 0', () => {
    const zeroSub = jwt.sign({}, cfg.secret, { subject: '0' });
    assert.throws(() => verifyToken(zeroSub, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });

  await t.test('id validation: rejects a negative sub', () => {
    const negativeSub = jwt.sign({}, cfg.secret, { subject: '-42' });
    assert.throws(() => verifyToken(negativeSub, cfg), (err) => err.code === 'UNAUTHENTICATED');
  });
});
