'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createGoogleVerifier } = require('../src/services/google');

test('google verifier', async (t) => {
  await t.test('stub returns a deterministic identity', async () => {
    const v = createGoogleVerifier({ mode: 'stub' });
    const id = await v.verifyIdToken('stub-token-juan');
    assert.equal(id.subject, 'stub-sub-juan');
    assert.equal(id.email, 'juan@example.com');
    assert.equal(id.emailVerified, true);
  });

  await t.test('stub can produce an unverified email for the linking test', async () => {
    const v = createGoogleVerifier({ mode: 'stub' });
    const id = await v.verifyIdToken('stub-token-unverified');
    assert.equal(id.emailVerified, false);
  });

  await t.test('stub rejects an unknown token', async () => {
    const v = createGoogleVerifier({ mode: 'stub' });
    await assert.rejects(() => v.verifyIdToken('nonsense'), (err) => err.code === 'INVALID_GOOGLE_TOKEN');
  });

  await t.test('http mode requires a client id', () => {
    assert.throws(() => createGoogleVerifier({ mode: 'http' }), /GOOGLE_CLIENT_ID/);
  });

  await t.test('an unsupported mode is rejected', () => {
    assert.throws(() => createGoogleVerifier({ mode: 'carrier-pigeon' }), /GOOGLE_MODE/);
  });
});
