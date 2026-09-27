'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { issueCode, checkCode } = require('../src/db/auth-codes');
const { codeKey } = require('../src/lib/auth-codes');

const key = codeKey('test-secret-value-at-least-32-chars');

test('auth codes db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const newUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'C')`,
      [`codes${seq}@example.com`],
    );
    return u.insertId;
  };
  const issue = (userId, purpose = 'verify_email') => issueCode(pool, { key, userId, purpose });
  const check = (userId, code, purpose = 'verify_email') =>
    checkCode(pool, { key, userId, purpose, code });
  const other = (code) => (code === '000000' ? '111111' : '000000');
  /// Moves a code's issue time back, so the resend limit no longer holds it.
  const age = (userId, purpose = 'verify_email') => pool.query(
    'UPDATE auth_codes SET created_at = DATE_SUB(NOW(), INTERVAL 2 MINUTE) WHERE user_id = ? AND purpose = ?',
    [userId, purpose],
  );
  const row = async (userId, purpose = 'verify_email') => {
    const [[r]] = await pool.query(
      'SELECT code_hash, attempts FROM auth_codes WHERE user_id = ? AND purpose = ?',
      [userId, purpose],
    );
    return r;
  };

  await t.test('a code is stored hashed, never as itself', async () => {
    const u = await newUser();
    const code = await issue(u);
    assert.match(code, /^\d{6}$/);
    const r = await row(u);
    assert.match(r.code_hash, /^[a-f0-9]{64}$/);
    assert.ok(!r.code_hash.includes(code));
    assert.equal(r.attempts, 0);
  });

  await t.test('the right code works once', async () => {
    const u = await newUser();
    const code = await issue(u);
    assert.equal(await check(u, code), true);
    assert.equal(await check(u, code), false, 'used');
    assert.equal(await row(u), undefined, 'the row is gone');
  });

  await t.test('a wrong code counts, and the fifth kills it', async () => {
    const u = await newUser();
    const code = await issue(u);
    for (let i = 1; i <= 4; i += 1) {
      assert.equal(await check(u, other(code)), false);
      assert.equal((await row(u)).attempts, i);
    }
    assert.equal(await check(u, other(code)), false);
    // The row stays behind as the lockout marker (see the next test).
    assert.equal((await row(u)).attempts, 5, 'kept at the fifth, as a lockout');
    assert.equal(await check(u, code), false, 'the right code is dead too');
  });

  await t.test('after five misses no new code is issued for fifteen minutes', async () => {
    const u = await newUser();
    const code = await issue(u);
    for (let i = 1; i <= 5; i += 1) assert.equal(await check(u, other(code)), false);
    const [[lock]] = await pool.query(
      `SELECT TIMESTAMPDIFF(SECOND, NOW(), expires_at) AS seconds
         FROM auth_codes WHERE user_id = ? AND purpose = 'verify_email'`,
      [u],
    );
    const seconds = Number(lock.seconds);
    assert.ok(seconds > 14 * 60 && seconds <= 15 * 60, `locked for ~15 minutes, got ${seconds}s`);

    await age(u);
    assert.equal(await issue(u), null, 'past the resend limit but still locked out');

    await pool.query(
      `UPDATE auth_codes SET expires_at = DATE_SUB(NOW(), INTERVAL 1 SECOND)
        WHERE user_id = ? AND purpose = 'verify_email'`,
      [u],
    );
    const fresh = await issue(u);
    assert.match(fresh, /^\d{6}$/, 'the lockout is over');
    assert.equal((await row(u)).attempts, 0, 'a new code starts with fresh attempts');
    assert.equal(await check(u, fresh), true);
  });

  await t.test('a locked code does not count further guesses', async () => {
    const u = await newUser();
    const code = await issue(u);
    for (let i = 1; i <= 5; i += 1) assert.equal(await check(u, other(code)), false);
    const [[before]] = await pool.query(
      "SELECT expires_at FROM auth_codes WHERE user_id = ? AND purpose = 'verify_email'", [u],
    );
    assert.equal(await check(u, other(code)), false);
    assert.equal(await check(u, code), false);
    const [[after]] = await pool.query(
      "SELECT attempts, expires_at FROM auth_codes WHERE user_id = ? AND purpose = 'verify_email'",
      [u],
    );
    assert.equal(after.attempts, 5, 'attempts stay at five');
    assert.deepEqual(after.expires_at, before.expires_at, 'the lockout is not extended');
  });

  await t.test('an expired code fails and is removed', async () => {
    const u = await newUser();
    const code = await issue(u);
    await pool.query(
      'UPDATE auth_codes SET expires_at = DATE_SUB(NOW(), INTERVAL 1 SECOND) WHERE user_id = ?', [u],
    );
    assert.equal(await check(u, code), false);
    assert.equal(await row(u), undefined);
  });

  await t.test('the lifetimes are 60 and 15 minutes', async () => {
    const u = await newUser();
    await issue(u, 'verify_email');
    await issue(u, 'reset_password');
    const [rows] = await pool.query(
      `SELECT purpose, TIMESTAMPDIFF(MINUTE, created_at, expires_at) AS minutes
         FROM auth_codes WHERE user_id = ? ORDER BY purpose`,
      [u],
    );
    assert.deepEqual(rows.map((r) => [r.purpose, Number(r.minutes)]),
      [['verify_email', 60], ['reset_password', 15]]);
  });

  await t.test('purposes do not cross', async () => {
    const u = await newUser();
    const code = await issue(u, 'verify_email');
    assert.equal(await check(u, code, 'reset_password'), false);
    assert.equal(await check(u, code, 'verify_email'), true);
  });

  await t.test("one person's code never works for another", async () => {
    const a = await newUser();
    const b = await newUser();
    const code = await issue(a);
    await issue(b);
    // Stored hashes are per user even if both drew the same digits.
    assert.notEqual((await row(a)).code_hash, (await row(b)).code_hash);
    // b's row never accepts a's code unless b happened to draw the same six
    // digits (one in a million) -- skip the check in that case.
    const [[bHash]] = await pool.query(
      "SELECT code_hash FROM auth_codes WHERE user_id = ? AND purpose = 'verify_email'", [b],
    );
    if (bHash.code_hash !== require('../src/lib/auth-codes').hashCode(key, {
      userId: b, purpose: 'verify_email', code,
    })) {
      assert.equal(await check(b, code), false);
    }
    assert.equal(await check(a, code), true, "a's code still works for a");
  });

  await t.test('within a minute a new code is held back; after, it replaces the old', async () => {
    const u = await newUser();
    const first = await issue(u);
    assert.equal(await issue(u), null, 'held back by the resend limit');

    await age(u);
    const second = await issue(u);
    assert.match(second, /^\d{6}$/);
    assert.equal((await row(u)).attempts, 0, 'a new code starts with fresh attempts');
    if (second !== first) {
      assert.equal(await check(u, first), false, 'the old code no longer works');
    }
    assert.equal(await check(u, second), true);
  });

  await t.test('two wrong guesses at once are both counted', async () => {
    const u = await newUser();
    const code = await issue(u);
    await Promise.all([check(u, other(code)), check(u, other(code))]);
    assert.equal((await row(u)).attempts, 2);
  });

  await t.test('checking with no code issued is simply false', async () => {
    assert.equal(await check(await newUser(), '123456'), false);
  });

  await t.test('two simultaneous first issues give exactly one code', async () => {
    const u = await newUser();
    const results = await Promise.all([issue(u), issue(u)]);
    const codes = results.filter((r) => r !== null);
    const nulls = results.filter((r) => r === null);
    assert.equal(codes.length, 1, 'exactly one code returned');
    assert.equal(nulls.length, 1, 'exactly one null returned');
    assert.match(codes[0], /^\d{6}$/);
    assert.equal(await check(u, codes[0]), true, 'the code checks true');
  });

  await t.test('two simultaneous re-issues after a minute give exactly one code', async () => {
    const u = await newUser();
    await issue(u);
    await age(u);
    const results = await Promise.all([issue(u), issue(u)]);
    const codes = results.filter((r) => r !== null);
    const nulls = results.filter((r) => r === null);
    assert.equal(codes.length, 1, 'exactly one code returned');
    assert.equal(nulls.length, 1, 'exactly one null returned');
    assert.match(codes[0], /^\d{6}$/);
    assert.equal(await check(u, codes[0]), true, 'the code checks true');
  });
});
