'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { issueToken, consumeToken, TTL_SECONDS } = require('../src/lib/auth-tokens');

test('auth tokens', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const newUser = async (email) => {
    const [r] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)',
      [email, 'x', 'T'],
    );
    return r.insertId;
  };

  await t.test('the raw token is never stored', async () => {
    const userId = await newUser('raw@example.com');
    const token = await issueToken(pool, { userId, purpose: 'verify_email' });

    const [rows] = await pool.query('SELECT * FROM auth_tokens WHERE user_id = ?', [userId]);
    assert.equal(rows.length, 1);
    const serialised = JSON.stringify(rows[0]);
    assert.ok(!serialised.includes(token),
      'the emailed token must not appear in any column -- a leaked table would '
      + 'otherwise hand over every outstanding credential');
    assert.equal(rows[0].token_hash.length, 64);
  });

  await t.test('a valid token resolves to its user', async () => {
    const userId = await newUser('valid@example.com');
    const token = await issueToken(pool, { userId, purpose: 'verify_email' });
    assert.deepEqual(await consumeToken(pool, { token, purpose: 'verify_email' }), { userId });
  });

  await t.test('a token works exactly once', async () => {
    const userId = await newUser('once@example.com');
    const token = await issueToken(pool, { userId, purpose: 'verify_email' });
    assert.ok(await consumeToken(pool, { token, purpose: 'verify_email' }));
    assert.equal(await consumeToken(pool, { token, purpose: 'verify_email' }), null);
  });

  await t.test('a token is bound to its purpose', async () => {
    const userId = await newUser('purpose@example.com');
    const token = await issueToken(pool, { userId, purpose: 'verify_email' });
    assert.equal(await consumeToken(pool, { token, purpose: 'reset_password' }), null,
      'a verification token must not be spendable as a password reset');
  });

  await t.test('an expired token is refused', async () => {
    const userId = await newUser('expired@example.com');
    const token = await issueToken(pool, { userId, purpose: 'reset_password' });
    await pool.query(
      'UPDATE auth_tokens SET expires_at = DATE_SUB(NOW(), INTERVAL 1 MINUTE) WHERE user_id = ?',
      [userId],
    );
    assert.equal(await consumeToken(pool, { token, purpose: 'reset_password' }), null);
  });

  await t.test('an unknown token is refused', async () => {
    assert.equal(
      await consumeToken(pool, { token: 'nonsense', purpose: 'verify_email' }), null);
  });

  await t.test('spending a reset invalidates that user\'s other resets', async () => {
    const userId = await newUser('rotate@example.com');
    const older = await issueToken(pool, { userId, purpose: 'reset_password' });
    const newer = await issueToken(pool, { userId, purpose: 'reset_password' });

    assert.ok(await consumeToken(pool, { token: newer, purpose: 'reset_password' }));
    assert.equal(await consumeToken(pool, { token: older, purpose: 'reset_password' }), null,
      'an older link must stop working once a newer one is used');
  });

  await t.test('a reset lives one hour and a verification one day', () => {
    assert.equal(TTL_SECONDS.reset_password, 3600);
    assert.equal(TTL_SECONDS.verify_email, 86400);
    assert.ok(TTL_SECONDS.reset_password < TTL_SECONDS.verify_email,
      'a reset token is worth more, so it must live less');
  });
});
