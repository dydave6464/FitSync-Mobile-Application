'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { setPremium } = require('../src/db/users');
const { parseArgs, resultLine } = require('../scripts/pro-grant');

test('pro:grant reads --user <id> and an optional --off', () => {
  assert.deepEqual(parseArgs(['--user', '34']), { userId: 34, on: true });
  assert.deepEqual(parseArgs(['--user', '34', '--off']), { userId: 34, on: false });
  assert.equal(parseArgs([]), null);
  assert.equal(parseArgs(['--user']), null);
  assert.equal(parseArgs(['--user', 'abc']), null);
  assert.equal(parseArgs(['--user', '0']), null);
});

test('pro:grant says it changed the grant, and when a paid period keeps the account Pro', () => {
  assert.equal(resultLine(34, true, { pro: true, source: 'granted' }), 'User 34: granted Pro on.');
  assert.equal(resultLine(34, false, { pro: false, source: null }), 'User 34: granted Pro off.');
  assert.equal(
    resultLine(34, false, { pro: true, source: 'paid', until: '2026-11-26T04:00:00.000Z' }),
    'User 34: granted Pro off (still Pro until 2026-11-26 from a paid period).',
  );
  // 20:00 UTC is 04:00 the next day in Manila: the UTC date is a day early.
  assert.equal(
    resultLine(34, false, { pro: true, source: 'paid', until: '2026-11-26T20:00:00.000Z' }),
    'User 34: granted Pro off (still Pro until 2026-11-27 from a paid period).',
  );
});

test('setPremium turns Pro on and off, and says when there is no such user', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const [u] = await pool.query("INSERT INTO users (email, password_hash, full_name) VALUES ('pro@b.com', 'x', 'P')");
  const premium = async () => Number((await pool.query('SELECT is_premium FROM users WHERE user_id = ?', [u.insertId]))[0][0].is_premium);
  assert.equal(await setPremium(pool, u.insertId, true), true);
  assert.equal(await premium(), 1);
  assert.equal(await setPremium(pool, u.insertId, true), true, 'already Pro still counts as found');
  assert.equal(await setPremium(pool, u.insertId, false), true);
  assert.equal(await premium(), 0);
  assert.equal(await setPremium(pool, 999999, true), false);
});
