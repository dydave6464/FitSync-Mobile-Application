'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { createApp } = require('../src/app');
const { createPool } = require('../src/db/pool');
const { testDbConfig } = require('./helpers/test-db');
const { silentLogger } = require('./helpers/test-app');

const build = (pool) => createApp({ config: { env: 'test' }, logger: silentLogger(), pool });

test('reports ok when the database is reachable', async () => {
  const pool = createPool(testDbConfig());
  try {
    const res = await request(build(pool)).get('/api/v1/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.data.status, 'ok');
    assert.equal(res.body.data.database, 'up');
    assert.equal(typeof res.body.data.uptime, 'number');
  } finally {
    await pool.end();
  }
});

test('reports degraded with 503 when the database is unreachable', async () => {
  const pool = createPool({ ...testDbConfig(), database: 'definitely_not_a_database' });
  try {
    const res = await request(build(pool)).get('/api/v1/health');
    assert.equal(res.status, 503);
    assert.equal(res.body.data.status, 'degraded');
    assert.equal(res.body.data.database, 'down');
  } finally {
    await pool.end();
  }
});

test('a database outage does not leak connection details', async () => {
  const pool = createPool({ ...testDbConfig(), database: 'definitely_not_a_database' });
  try {
    const res = await request(build(pool)).get('/api/v1/health');
    const body = JSON.stringify(res.body);
    assert.doesNotMatch(body, /password/i);
    assert.doesNotMatch(body, new RegExp(testDbConfig().user));
  } finally {
    await pool.end();
  }
});
