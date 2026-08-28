'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createGoogleVerifier } = require('../src/services/google');
const httpClient = require('../src/services/google/http-client');

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

  await t.test('http mode with a clientId builds a client exposing the expected interface', () => {
    const v = createGoogleVerifier({ mode: 'http', clientId: 'test-client-id' });
    assert.equal(typeof v.verifyIdToken, 'function');
  });
});

test('google http client', async (t) => {
  // Helper to monkey-patch OAuth2Client.prototype.verifyIdToken without leaking state
  function withFakeOAuth2Client(mockTicket, fn) {
    const { OAuth2Client } = require('google-auth-library');
    const original = OAuth2Client.prototype.verifyIdToken;
    OAuth2Client.prototype.verifyIdToken = async () => mockTicket;
    return fn().finally(() => {
      OAuth2Client.prototype.verifyIdToken = original;
    });
  }

  await t.test('successful verification maps payload fields correctly', async () => {
    const mockTicket = {
      getPayload: () => ({
        sub: 'google-sub-123',
        email: 'user@example.com',
        email_verified: true,
        name: 'Test User',
      }),
    };
    return withFakeOAuth2Client(mockTicket, async () => {
      const v = httpClient.create('test-client-id');
      const id = await v.verifyIdToken('valid-token');
      assert.equal(id.subject, 'google-sub-123');
      assert.equal(id.email, 'user@example.com');
      assert.equal(id.emailVerified, true);
      assert.equal(id.fullName, 'Test User');
    });
  });

  await t.test('email_verified: false is preserved', async () => {
    const mockTicket = {
      getPayload: () => ({
        sub: 'google-sub-123',
        email: 'unverified@example.com',
        email_verified: false,
        name: 'Unverified User',
      }),
    };
    return withFakeOAuth2Client(mockTicket, async () => {
      const v = httpClient.create('test-client-id');
      const id = await v.verifyIdToken('valid-token');
      assert.equal(id.emailVerified, false);
    });
  });

  await t.test('missing optional fields become null', async () => {
    const mockTicket = {
      getPayload: () => ({
        sub: 'google-sub-123',
        // no email, email_verified, or name
      }),
    };
    return withFakeOAuth2Client(mockTicket, async () => {
      const v = httpClient.create('test-client-id');
      const id = await v.verifyIdToken('valid-token');
      assert.equal(id.email, null);
      assert.equal(id.emailVerified, false);
      assert.equal(id.fullName, null);
    });
  });

  await t.test('a bad token (verifyIdToken throws) produces INVALID_GOOGLE_TOKEN', async () => {
    const { OAuth2Client } = require('google-auth-library');
    const original = OAuth2Client.prototype.verifyIdToken;
    OAuth2Client.prototype.verifyIdToken = async () => {
      const err = new Error('Token signature verification failed');
      err.code = null; // Real token errors don't have system error codes
      throw err;
    };
    try {
      const v = httpClient.create('test-client-id');
      await assert.rejects(
        () => v.verifyIdToken('bad-token'),
        (err) => err.code === 'INVALID_GOOGLE_TOKEN',
      );
    } finally {
      OAuth2Client.prototype.verifyIdToken = original;
    }
  });

  await t.test('payload without sub throws INVALID_GOOGLE_TOKEN', async () => {
    const mockTicket = {
      getPayload: () => ({
        email: 'user@example.com',
        // missing sub
      }),
    };
    return withFakeOAuth2Client(mockTicket, async () => {
      const v = httpClient.create('test-client-id');
      await assert.rejects(
        () => v.verifyIdToken('valid-token'),
        (err) => err.code === 'INVALID_GOOGLE_TOKEN',
      );
    });
  });

  await t.test('null payload throws INVALID_GOOGLE_TOKEN', async () => {
    const mockTicket = {
      getPayload: () => null,
    };
    return withFakeOAuth2Client(mockTicket, async () => {
      const v = httpClient.create('test-client-id');
      await assert.rejects(
        () => v.verifyIdToken('valid-token'),
        (err) => err.code === 'INVALID_GOOGLE_TOKEN',
      );
    });
  });

  await t.test('a transport failure (DNS, timeout, etc.) throws a plain Error, not INVALID_GOOGLE_TOKEN', async () => {
    const { OAuth2Client } = require('google-auth-library');
    const original = OAuth2Client.prototype.verifyIdToken;
    OAuth2Client.prototype.verifyIdToken = async () => {
      const err = new Error('getaddrinfo ENOTFOUND keys.google.com');
      err.code = 'ENOTFOUND';
      throw err;
    };
    try {
      const v = httpClient.create('test-client-id');
      await assert.rejects(
        () => v.verifyIdToken('valid-token'),
        (err) => {
          // Should be a plain Error, not AppError
          assert.equal(err.name, 'Error');
          assert.equal(err.code, undefined); // plain Error has no code property
          assert.ok(err.cause); // But should have the original error attached
          return true;
        },
      );
    } finally {
      OAuth2Client.prototype.verifyIdToken = original;
    }
  });

  await t.test('an abort error is recognized as transport failure', async () => {
    const { OAuth2Client } = require('google-auth-library');
    const original = OAuth2Client.prototype.verifyIdToken;
    OAuth2Client.prototype.verifyIdToken = async () => {
      const err = new Error('Request aborted');
      err.name = 'AbortError';
      throw err;
    };
    try {
      const v = httpClient.create('test-client-id');
      await assert.rejects(
        () => v.verifyIdToken('valid-token'),
        (err) => {
          assert.equal(err.name, 'Error');
          assert.equal(err.code, undefined);
          assert.ok(err.cause);
          return true;
        },
      );
    } finally {
      OAuth2Client.prototype.verifyIdToken = original;
    }
  });
});
