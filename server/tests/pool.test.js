'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createPool } = require('../src/db/pool');
const { testDbConfig } = require('./helpers/test-db');

test('pool connects and executes a query', async () => {
  const pool = createPool(testDbConfig());
  try {
    const [rows] = await pool.query('SELECT 1 AS ok');
    assert.equal(rows[0].ok, 1);
  } finally {
    await pool.end();
  }
});

test('pool reports utf8mb4 so Filipino text is storable', async () => {
  const pool = createPool(testDbConfig());
  try {
    const [rows] = await pool.query("SHOW VARIABLES LIKE 'character_set_client'");
    assert.equal(rows[0].Value, 'utf8mb4');
  } finally {
    await pool.end();
  }
});

test('pool surfaces connection failures rather than hanging', async () => {
  const pool = createPool({ ...testDbConfig(), database: 'definitely_not_a_database' });
  try {
    await assert.rejects(() => pool.query('SELECT 1'));
  } finally {
    await pool.end();
  }
});

// "Today" is Manila's date on any host: CURDATE(), NOW() and WEEKDAY() follow
// the session's zone, and a host left on UTC would otherwise roll the day
// over at 08:00 Manila time. Two connections held at once, so a zone set on
// only the first connection the pool happens to open would still fail.
test('every pooled connection runs on Manila time', async () => {
  const pool = createPool({ ...testDbConfig(), connectionLimit: 2 });
  const a = await pool.getConnection();
  const b = await pool.getConnection();
  try {
    for (const conn of [a, b]) {
      const [[row]] = await conn.query(
        'SELECT @@session.time_zone AS tz, TIMESTAMPDIFF(MINUTE, UTC_TIMESTAMP(), NOW()) AS offset_min',
      );
      assert.equal(row.tz, '+08:00');
      assert.equal(row.offset_min, 480);
    }
  } finally {
    a.release();
    b.release();
    await pool.end();
  }
});
