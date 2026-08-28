'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { hashPassword, verifyPassword } = require('../src/lib/passwords');

test('passwords', async (t) => {
  await t.test('a hash never equals the plaintext', async () => {
    const hash = await hashPassword('correct horse battery staple');
    assert.notEqual(hash, 'correct horse battery staple');
    assert.ok(hash.length > 20);
  });

  await t.test('verifies a correct password', async () => {
    const hash = await hashPassword('s3cret-pass');
    assert.equal(await verifyPassword('s3cret-pass', hash), true);
  });

  await t.test('rejects a wrong password', async () => {
    const hash = await hashPassword('s3cret-pass');
    assert.equal(await verifyPassword('wrong', hash), false);
  });

  await t.test('returns false for a null hash rather than throwing', async () => {
    // A Google-only account has no password. Signing in with a password must
    // fail cleanly, not crash the route.
    assert.equal(await verifyPassword('anything', null), false);
  });
});
