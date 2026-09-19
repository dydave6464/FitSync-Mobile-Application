'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('shared_reports schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('sr@example.com', 'x', 'S')",
  );
  const userId = u.insertId;

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const insert = (token) => pool.query(
    `INSERT INTO shared_reports
       (user_id, token, period, window_start, window_end, report_json, expires_at)
     VALUES (?, ?, 'week', '2026-09-01', '2026-09-28', ?, DATE_ADD(NOW(), INTERVAL 30 DAY))`,
    [userId, token, JSON.stringify({ volume: { totalKg: 1550 } })],
  );

  await t.test('stores a report and reads its json back', async () => {
    await insert('a'.repeat(43));
    const [[row]] = await pool.query(
      'SELECT report_json, period FROM shared_reports WHERE token = ?', ['a'.repeat(43)],
    );
    const json = typeof row.report_json === 'string'
      ? JSON.parse(row.report_json) : row.report_json;
    assert.equal(json.volume.totalKg, 1550);
    assert.equal(row.period, 'week');
  });

  await t.test('a token is unique', async () => {
    await assert.rejects(() => insert('a'.repeat(43)), /Duplicate entry/);
  });

  // The token is the only credential the page has. A second row sharing one
  // would hand a coach someone else's report.
  await t.test('two reports for one user get their own rows', async () => {
    await insert('b'.repeat(43));
    const [rows] = await pool.query(
      'SELECT token FROM shared_reports WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 2);
  });

  await t.test('deleting the user takes their reports with them', async () => {
    const [u2] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('sr2@example.com', 'x', 'S')",
    );
    await pool.query(
      `INSERT INTO shared_reports
         (user_id, token, period, window_start, window_end, report_json, expires_at)
       VALUES (?, ?, 'week', '2026-09-01', '2026-09-28', '{}', DATE_ADD(NOW(), INTERVAL 30 DAY))`,
      [u2.insertId, 'c'.repeat(43)],
    );
    await pool.query('DELETE FROM users WHERE user_id = ?', [u2.insertId]);
    const [rows] = await pool.query(
      'SELECT token FROM shared_reports WHERE token = ?', ['c'.repeat(43)],
    );
    assert.equal(rows.length, 0);
  });
});
