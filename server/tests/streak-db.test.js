'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { activeDates, readStreak } = require('../src/db/streak');

test('streak db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const newUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'S')`,
      [`streak${seq}@example.com`],
    );
    return u.insertId;
  };

  /// The server's date [n] days ago, as 'YYYY-MM-DD'.
  const ago = async (n) => {
    const [[{ d }]] = await pool.query(
      `SELECT DATE_FORMAT(CURDATE() - INTERVAL ? DAY, '%Y-%m-%d') AS d`, [n],
    );
    return d;
  };

  /// A habit of its own, ticked [daysAgo]. Raw SQL: these tests are about
  /// what is READ as activity, not how a tick is written.
  const tick = async (userId, daysAgo, { active = true } = {}) => {
    const [h] = await pool.query(
      `INSERT INTO routine_habits (user_id, title, is_active) VALUES (?, 'H', ?)`,
      [userId, active],
    );
    await pool.query(
      `INSERT INTO routine_checks (habit_id, check_date)
       VALUES (?, DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
      [h.insertId, daysAgo],
    );
  };

  const session = (userId, daysAgo, status = 'completed') => pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date)
     VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
    [userId, status, daysAgo],
  );

  await t.test('ticks and completed workouts are activity, a deleted habit included', async () => {
    const u = await newUser();
    await tick(u, 0);
    await tick(u, 1, { active: false });
    await session(u, 2);
    assert.deepEqual((await activeDates(pool, u)).sort(), [await ago(2), await ago(1), await ago(0)]);
  });

  await t.test('an abandoned or unfinished workout is not activity', async () => {
    const u = await newUser();
    await session(u, 0, 'abandoned');
    await session(u, 1, 'in_progress');
    assert.deepEqual(await activeDates(pool, u), []);
  });

  await t.test("another user's activity is not counted", async () => {
    const a = await newUser();
    const b = await newUser();
    await tick(b, 0);
    await session(b, 1);
    assert.deepEqual(await activeDates(pool, a), []);
  });

  await t.test('a tick and a workout on one day count once', async () => {
    const u = await newUser();
    await tick(u, 0);
    await session(u, 0);
    assert.equal((await activeDates(pool, u)).length, 1);
  });

  await t.test("the streak counts back from the server's today", async () => {
    const u = await newUser();
    await tick(u, 0);
    await session(u, 1);
    await tick(u, 2);
    const s = await readStreak(pool, u);
    assert.equal(s.current, 3);
    assert.equal(s.best, 3);
    assert.equal(s.todayActive, true);
    assert.equal(s.week.length, 7);
    const today = await ago(0);
    assert.deepEqual(s.week.find((d) => d.date === today), { date: today, active: true });
  });
});
