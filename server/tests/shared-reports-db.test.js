'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  createSharedReport, readSharedReport, SHARE_TTL_DAYS,
} = require('../src/db/shared-reports');

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
      'UPDATE shared_reports SET expires_at = DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE token = ?',
      [token],
    );

    assert.equal(await readSharedReport(pool, token), null);
  });

  await t.test('a new report expires 30 days out', async () => {
    const userId = await makeUser('c5@example.com');
    const { token, expiresAt } = await createSharedReport(pool, userId, payload);
    assert.equal(SHARE_TTL_DAYS, 30);

    const [[row]] = await pool.query(
      'SELECT DATEDIFF(expires_at, NOW()) AS days FROM shared_reports WHERE token = ?',
      [token],
    );
    assert.equal(Number(row.days), 30);
    assert.ok(expiresAt instanceof Date);
  });
});
