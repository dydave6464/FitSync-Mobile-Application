'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('ad details schema (046)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('advertisements gains the seven columns with their types and defaults', async () => {
    const [rows] = await pool.query('SHOW COLUMNS FROM advertisements');
    const col = Object.fromEntries(rows.map((r) => [r.Field, [r.Type, r.Null, r.Default]]));
    assert.deepEqual(col.link_url, ['varchar(500)', 'YES', null]);
    assert.deepEqual(col.advertiser, ['varchar(120)', 'NO', '']);
    assert.deepEqual(col.amount_php, ['decimal(10,2)', 'NO', '0.00']);
    assert.deepEqual(col.starts_on, ['date', 'YES', null]);
    assert.deepEqual(col.ends_on, ['date', 'YES', null]);
    assert.deepEqual(col.views, ['int unsigned', 'NO', '0']);
    assert.deepEqual(col.taps, ['int unsigned', 'NO', '0']);
  });

  await t.test('an ad inserted with only the 006 columns takes the defaults', async () => {
    const [r] = await pool.query("INSERT INTO advertisements (title, image_url) VALUES ('Old ad', 'ads/x.jpg')");
    const [[row]] = await pool.query(
      'SELECT link_url, advertiser, amount_php, starts_on, ends_on, views, taps FROM advertisements WHERE ad_id = ?',
      [r.insertId],
    );
    assert.deepEqual({ ...row }, {
      link_url: null, advertiser: '', amount_php: '0.00', starts_on: null, ends_on: null, views: 0, taps: 0,
    });
  });
});
