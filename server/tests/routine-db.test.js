'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

// Fixed days, so weekday logic never depends on when the suite runs.
const MONDAY = '2026-09-21';
const TUESDAY = '2026-09-22';

test('routine db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const newUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'R')`,
      [`routine${seq}@example.com`],
    );
    return u.insertId;
  };

  /// A habit written directly. Raw SQL: these tests are about what the
  /// functions REPORT, independent of how the route validates input.
  const habit = async (userId, {
    title = 'Stretch', time = null, durationMin = null,
    weekdays = [1, 2, 3, 4, 5, 6, 7], active = true,
  } = {}) => {
    const [h] = await pool.query(
      `INSERT INTO routine_habits (user_id, title, scheduled_time, duration_min, is_active)
       VALUES (?, ?, ?, ?, ?)`,
      [userId, title, time, durationMin, active],
    );
    for (const d of weekdays) {
      await pool.query(
        'INSERT INTO routine_habit_days (habit_id, weekday) VALUES (?, ?)',
        [h.insertId, d],
      );
    }
    return h.insertId;
  };

  await t.test('a duration outside 1-600 is refused by the table', async () => {
    const u = await newUser();
    for (const bad of [0, 601]) {
      await assert.rejects(
        () => habit(u, { durationMin: bad }),
        (err) => err.code === 'ER_CHECK_CONSTRAINT_VIOLATED',
        `durationMin ${bad}`,
      );
    }
  });

  await t.test('a weekday outside 1-7 is refused by the table', async () => {
    const u = await newUser();
    const h = await habit(u, { weekdays: [] });
    for (const bad of [0, 8]) {
      await assert.rejects(
        () => pool.query('INSERT INTO routine_habit_days (habit_id, weekday) VALUES (?, ?)', [h, bad]),
        (err) => err.code === 'ER_CHECK_CONSTRAINT_VIOLATED',
        `weekday ${bad}`,
      );
    }
  });

  await t.test('a weekday is listed once per habit, and a day ticked once', async () => {
    const u = await newUser();
    const h = await habit(u, { weekdays: [1] });
    await assert.rejects(
      () => pool.query('INSERT INTO routine_habit_days (habit_id, weekday) VALUES (?, 1)', [h]),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
    await pool.query('INSERT INTO routine_checks (habit_id, check_date) VALUES (?, ?)', [h, MONDAY]);
    await assert.rejects(
      () => pool.query('INSERT INTO routine_checks (habit_id, check_date) VALUES (?, ?)', [h, MONDAY]),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  // Task 2 appends its subtests here, reusing newUser, habit, MONDAY and TUESDAY.
  void TUESDAY;
});
