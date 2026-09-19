'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  createSharedReport, readSharedReport, SHARE_TTL_DAYS,
} = require('../src/db/shared-reports');
const { hashToken } = require('../src/lib/auth-tokens');

test('shared reports db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const makeUser = async (email, fullName = 'Juan Dela Cruz') => {
    const [res] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name) VALUES (?, ?, ?)',
      [email, 'x', fullName],
    );
    return res.insertId;
  };

  const payload = {
    period: 'week',
    windowStart: '2026-09-12',
    windowEnd: '2026-09-19',
    report: { volume: { totalKg: 1550 } },
  };

  await t.test('a created report reads back by its token', async () => {
    const userId = await makeUser('c1@example.com');
    const { token } = await createSharedReport(pool, userId, payload);

    const found = await readSharedReport(pool, token);
    assert.equal(found.userId, userId);
    assert.equal(found.report.volume.totalKg, 1550);
    assert.equal(found.period, 'week');
  });

  // The page captions the report with who sent it, and reads it from the row's
  // join rather than from the snapshot -- a renamed user should not have an
  // old name on a live link.
  await t.test('the report carries its owner name, read live', async () => {
    const userId = await makeUser('c2@example.com', 'Maria Santos');
    const { token } = await createSharedReport(pool, userId, payload);

    // Renamed AFTER sharing. A name frozen into the row at insert would
    // still read 'Maria Santos' here; the join reads what is true now.
    await pool.query('UPDATE users SET full_name = ? WHERE user_id = ?',
      ['Maria Reyes', userId]);

    assert.equal((await readSharedReport(pool, token)).fullName, 'Maria Reyes');
  });

  // 43 base64url characters from 32 random bytes. Guessing is not a threat
  // model at that width; a short or derived token would make it one.
  await t.test('tokens are 43 characters and never repeat', async () => {
    const userId = await makeUser('c3@example.com');
    const seen = new Set();
    for (let i = 0; i < 20; i += 1) {
      const { token } = await createSharedReport(pool, userId, payload);
      assert.match(token, /^[A-Za-z0-9_-]{43}$/);
      seen.add(token);
    }
    assert.equal(seen.size, 20);
  });

  await t.test('an unknown token is null, not an error', async () => {
    assert.equal(await readSharedReport(pool, 'z'.repeat(43)), null);
  });

  // Expiry is enforced on the way out, so a link stops working without
  // anything having to sweep the table.
  await t.test('an expired report reads as null', async () => {
    const userId = await makeUser('c4@example.com');
    const { token } = await createSharedReport(pool, userId, payload);
    await pool.query(
      `UPDATE shared_reports SET expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY)
        WHERE token_hash = ?`,
      [hashToken(token)],
    );

    assert.equal(await readSharedReport(pool, token), null);
  });

  await t.test('a new report expires 30 days out', async () => {
    const userId = await makeUser('c5@example.com');
    const { token, expiresAt } = await createSharedReport(pool, userId, payload);
    assert.equal(SHARE_TTL_DAYS, 30);

    const [[row]] = await pool.query(
      'SELECT DATEDIFF(expires_at, NOW()) AS days FROM shared_reports WHERE token_hash = ?',
      [hashToken(token)],
    );
    assert.equal(Number(row.days), 30);
    assert.ok(expiresAt instanceof Date);
  });

  // The stored row must be useless to anyone who reads the table: only the
  // SHA-256 of the token is there, never the token. Same policy as
  // auth_tokens, and for a longer-lived credential than either of those.
  await t.test('the plaintext token is never in the stored row', async () => {
    const userId = await makeUser('c6@example.com');
    const { token } = await createSharedReport(pool, userId, payload);

    const [rows] = await pool.query(
      'SELECT * FROM shared_reports WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 1);

    // The whole row, every column, serialised -- not just the one we expect
    // the token to have been in.
    assert.doesNotMatch(JSON.stringify(rows[0]), new RegExp(escapeForRegExp(token)));
    assert.equal(rows[0].token_hash, hashToken(token));
    assert.match(rows[0].token_hash, /^[0-9a-f]{64}$/);
    assert.notEqual(rows[0].token_hash, token);
  });

  // The old CHAR(43) column collated as utf8mb4_unicode_ci, so a token whose
  // case had been mangled in transit still matched. A hex digest cannot be
  // mangled that way -- and the lookup is by hash, so a changed token does
  // not resolve at all.
  await t.test('a case-mangled token does not resolve', async () => {
    const userId = await makeUser('c7@example.com');
    const { token } = await createSharedReport(pool, userId, payload);

    assert.notEqual(await readSharedReport(pool, token), null, 'the real token works');

    // Flip the case of the first character that HAS a case, so the mangled
    // token is guaranteed to differ -- toUpperCase() on a token that happened
    // to hold no lowercase letters would otherwise be the token itself.
    const i = [...token].findIndex((c) => c.toLowerCase() !== c.toUpperCase());
    assert.ok(i >= 0, '43 base64url characters always include a letter');
    const flipped = token[i] === token[i].toLowerCase()
      ? token[i].toUpperCase()
      : token[i].toLowerCase();
    const mangled = token.slice(0, i) + flipped + token.slice(i + 1);

    assert.notEqual(mangled, token);
    assert.equal(await readSharedReport(pool, mangled), null);
  });

  await t.test('a missing token is null rather than a crash', async () => {
    assert.equal(await readSharedReport(pool, ''), null);
    assert.equal(await readSharedReport(pool, undefined), null);
  });
});

// base64url has no regex metacharacters except '-', which is inert outside a
// character class -- but escape anyway rather than depend on that.
function escapeForRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
