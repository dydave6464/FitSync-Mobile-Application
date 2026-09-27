'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  generateCode, codeKey, hashCode, sameHash, normaliseCode,
  TTL_MINUTES, MAX_ATTEMPTS, RESEND_COOLDOWN_SECONDS,
} = require('../src/lib/auth-codes');

const KEY = codeKey('test-secret-value-at-least-32-chars');

test('a code is always six digits, leading zeros kept', () => {
  for (let i = 0; i < 500; i += 1) assert.match(generateCode(), /^\d{6}$/);
});

test('the rules match the design', () => {
  assert.deepEqual(TTL_MINUTES, { verify_email: 60, reset_password: 15 });
  assert.equal(MAX_ATTEMPTS, 5);
  assert.equal(RESEND_COOLDOWN_SECONDS, 60);
});

test('the key is derived from the secret, not the secret itself', () => {
  assert.ok(Buffer.isBuffer(KEY));
  assert.notEqual(KEY.toString('utf8'), 'test-secret-value-at-least-32-chars');
  assert.ok(!KEY.equals(codeKey('another-secret-value-at-least-32-chars')));
  assert.throws(() => codeKey(''), /secret/);
  assert.throws(() => codeKey(undefined), /secret/);
});

test('a hash is tied to the user, the purpose and the key', () => {
  const base = { userId: 7, purpose: 'verify_email', code: '048213' };
  const h = hashCode(KEY, base);
  assert.match(h, /^[a-f0-9]{64}$/);
  assert.ok(!h.includes('048213'), 'the code itself is not in the hash');
  assert.equal(hashCode(KEY, base), h, 'stable');
  assert.notEqual(hashCode(KEY, { ...base, userId: 8 }), h);
  assert.notEqual(hashCode(KEY, { ...base, purpose: 'reset_password' }), h);
  assert.notEqual(hashCode(KEY, { ...base, code: '048214' }), h);
  assert.notEqual(hashCode(codeKey('other-secret-value-at-least-32-char'), base), h);
});

test('hashes compare equal only when they are', () => {
  const h = hashCode(KEY, { userId: 1, purpose: 'verify_email', code: '123456' });
  assert.equal(sameHash(h, h), true);
  assert.equal(sameHash(h, hashCode(KEY, { userId: 1, purpose: 'verify_email', code: '123457' })), false);
  assert.equal(sameHash(h, ''), false);
  assert.equal(sameHash(h, 'abc'), false);
});

test('a code is accepted with spaces, and only as six digits', () => {
  assert.equal(normaliseCode('048213'), '048213');
  assert.equal(normaliseCode(' 048 213 '), '048213');
  for (const bad of ['04821', '0482131', 'abcdef', '04821a', '', null, undefined, 48213, {}]) {
    assert.equal(normaliseCode(bad), null, String(bad));
  }
});
