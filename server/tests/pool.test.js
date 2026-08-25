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
