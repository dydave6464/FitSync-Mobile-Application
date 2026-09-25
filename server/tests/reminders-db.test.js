'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const reminders = require('../src/db/reminders');

const DEFAULTS = {
  habitsEnabled: true, habitLeadMin: 15,
  workoutEnabled: false, workoutTime: '07:00',
  checkinEnabled: false, checkinTime: '07:00',
};

test('reminder settings db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const newUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'R')`,
      [`rem${seq}@example.com`],
    );
    return u.insertId;
  };
  const rowCount = async (userId) => {
    const [[{ n }]] = await pool.query(
      'SELECT COUNT(*) AS n FROM reminder_settings WHERE user_id = ?', [userId],
    );
    return Number(n);
  };

  await t.test('an account with no row reads the defaults, and reading creates none', async () => {
    const u = await newUser();
    assert.deepEqual(await reminders.readReminderSettings(pool, u), DEFAULTS);
    assert.equal(await rowCount(u), 0);
  });

  await t.test('an update changes only its fields and creates the row', async () => {
    const u = await newUser();
    const s = await reminders.updateReminderSettings(pool, u, { workoutEnabled: true, workoutTime: '18:30' });
    assert.deepEqual(s, { ...DEFAULTS, workoutEnabled: true, workoutTime: '18:30' });
    assert.equal(await rowCount(u), 1);
  });

  await t.test('a second update keeps the first', async () => {
    const u = await newUser();
    await reminders.updateReminderSettings(pool, u, { habitLeadMin: 5 });
    const s = await reminders.updateReminderSettings(pool, u, { checkinEnabled: true });
    assert.equal(s.habitLeadMin, 5);
    assert.equal(s.checkinEnabled, true);
    assert.equal(await rowCount(u), 1);
  });

  await t.test("one user's settings never touch another's", async () => {
    const a = await newUser();
    const b = await newUser();
    await reminders.updateReminderSettings(pool, a, { habitsEnabled: false });
    assert.deepEqual(await reminders.readReminderSettings(pool, b), DEFAULTS);
  });
});
