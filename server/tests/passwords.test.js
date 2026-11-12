'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  hashPassword, verifyPassword, confirmPassword, MIN_PASSWORD_LENGTH, MAX_PASSWORD_LENGTH,
} = require('../src/lib/passwords');

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

  await t.test('the length rule lives here: at least 8, at most bcrypt\'s 72', () => {
    assert.equal(MIN_PASSWORD_LENGTH, 8);
    assert.equal(MAX_PASSWORD_LENGTH, 72);
  });

  // The one re-confirmation check, shared by POST /auth/password and
  // POST /account/delete so the two can never disagree about a password.
  await t.test('confirmPassword accepts the password, trimmed as login trims it', async () => {
    const hash = await hashPassword('s3cret-pass');
    await confirmPassword('s3cret-pass', hash);
    await confirmPassword('  s3cret-pass ', hash);
  });

  await t.test('confirmPassword answers WRONG_PASSWORD for anything that is not it', async () => {
    const hash = await hashPassword('s3cret-pass');
    for (const typed of ['wrong', '', '   ', undefined, null, 12345678, 'x'.repeat(MAX_PASSWORD_LENGTH + 1)]) {
      await assert.rejects(confirmPassword(typed, hash), (err) => {
        assert.equal(err.status, 400, `typed ${String(typed).slice(0, 12)}`);
        assert.equal(err.code, 'WRONG_PASSWORD');
        assert.equal(err.message, "That password isn't right.");
        return true;
      });
    }
    await assert.rejects(confirmPassword('s3cret-pass', null), { code: 'WRONG_PASSWORD' });
  });
});
