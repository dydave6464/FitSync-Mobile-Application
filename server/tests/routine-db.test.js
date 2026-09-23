'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const routine = require('../src/db/routine');

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

  await t.test('the day lists active habits on its weekday, timed first', async () => {
    const u = await newUser();
    await habit(u, { title: 'Walk', weekdays: [1] });
    await habit(u, { title: 'Mobility', time: '06:30', durationMin: 8, weekdays: [1] });
    await habit(u, { title: 'Stretch', time: '21:00', weekdays: [1, 3] });
    await habit(u, { title: 'Read', weekdays: [2] });              // Tuesday only
    await habit(u, { title: 'Old', weekdays: [1], active: false }); // deleted

    const day = await routine.readDay(pool, u, MONDAY);

    assert.equal(day.date, MONDAY);
    assert.deepEqual(day.habits.map((h) => h.title), ['Mobility', 'Stretch', 'Walk']);
    assert.deepEqual(day.habits[0], {
      habitId: day.habits[0].habitId, title: 'Mobility', time: '06:30',
      durationMin: 8, weekdays: [1], done: false,
    });
    assert.deepEqual(day.habits[1].weekdays, [1, 3]);
  });

  await t.test('a habit on Monday only is not listed on Tuesday', async () => {
    const u = await newUser();
    await habit(u, { title: 'Mon', weekdays: [1] });
    assert.equal((await routine.readDay(pool, u, TUESDAY)).habits.length, 0);
  });

  await t.test("another user's habits are not listed", async () => {
    const a = await newUser();
    const b = await newUser();
    await habit(b, { weekdays: [1] });
    assert.equal((await routine.readDay(pool, a, MONDAY)).habits.length, 0);
  });

  await t.test('ticking marks it done for that day only; twice is harmless', async () => {
    const u = await newUser();
    const h = await habit(u);
    assert.deepEqual(await routine.setCheck(pool, u, h, true, MONDAY), { done: true });
    assert.deepEqual(await routine.setCheck(pool, u, h, true, MONDAY), { done: true });

    const [rows] = await pool.query('SELECT check_date FROM routine_checks WHERE habit_id = ?', [h]);
    assert.equal(rows.length, 1);
    assert.equal((await routine.readDay(pool, u, MONDAY)).habits[0].done, true);
    assert.equal((await routine.readDay(pool, u, TUESDAY)).habits[0].done, false);

    assert.deepEqual(await routine.setCheck(pool, u, h, false, MONDAY), { done: false });
    assert.deepEqual(await routine.setCheck(pool, u, h, false, MONDAY), { done: false });
    assert.equal((await routine.readDay(pool, u, MONDAY)).habits[0].done, false);
  });

  await t.test('ticking a habit not scheduled that day is refused', async () => {
    const u = await newUser();
    const h = await habit(u, { weekdays: [2] });
    await assert.rejects(
      () => routine.setCheck(pool, u, h, true, MONDAY),
      (err) => err.status === 400 && err.code === 'HABIT_NOT_TODAY',
    );
  });

  await t.test("another user's or a deleted habit cannot be ticked", async () => {
    const a = await newUser();
    const b = await newUser();
    const theirs = await habit(b);
    const gone = await habit(a, { active: false });
    assert.equal(await routine.setCheck(pool, a, theirs, true, MONDAY), null);
    assert.equal(await routine.setCheck(pool, a, gone, true, MONDAY), null);
  });

  await t.test('creating stores the habit and its weekdays', async () => {
    const u = await newUser();
    const created = await routine.createHabit(pool, u, {
      title: 'Plank', time: '07:15', durationMin: 5, weekdays: [1, 5],
    });
    assert.equal(created.title, 'Plank');
    assert.equal(created.time, '07:15');
    assert.equal(created.durationMin, 5);
    assert.deepEqual(created.weekdays, [1, 5]);
    assert.equal(created.done, false);

    const bare = await routine.createHabit(pool, u, { title: 'Water', weekdays: [3] });
    assert.equal(bare.time, null);
    assert.equal(bare.durationMin, null);
  });

  await t.test('updating changes only the fields given, and can clear', async () => {
    const u = await newUser();
    const h = await habit(u, { title: 'Run', time: '06:00', durationMin: 30, weekdays: [1] });

    let updated = await routine.updateHabit(pool, u, h, { title: 'Easy run' });
    assert.equal(updated.title, 'Easy run');
    assert.equal(updated.time, '06:00');

    updated = await routine.updateHabit(pool, u, h, { time: null, durationMin: null, weekdays: [2, 4] });
    assert.equal(updated.time, null);
    assert.equal(updated.durationMin, null);
    assert.deepEqual(updated.weekdays, [2, 4]);

    assert.equal(await routine.updateHabit(pool, await newUser(), h, { title: 'x' }), null);
  });

  await t.test('deleting hides the habit and keeps its past ticks', async () => {
    const u = await newUser();
    const h = await habit(u);
    await routine.setCheck(pool, u, h, true, MONDAY);

    assert.equal(await routine.deactivateHabit(pool, u, h), true);
    assert.equal(await routine.deactivateHabit(pool, u, h), false, 'already gone');
    assert.equal((await routine.readDay(pool, u, TUESDAY)).habits.length, 0);
    const [rows] = await pool.query('SELECT 1 FROM routine_checks WHERE habit_id = ?', [h]);
    assert.equal(rows.length, 1, 'the history outlives the habit');
  });

  // The workout item. A plan is written directly; is_active defaults to TRUE.
  const plan = async (userId, name = 'Upper Body') => pool.query(
    `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min)
     VALUES (?, ?, 'full_body', 3, 45)`,
    [userId, name],
  );
  const trainingDays = async (userId, days) => {
    for (const d of days) {
      await pool.query('INSERT INTO user_training_days (user_id, weekday) VALUES (?, ?)', [userId, d]);
    }
  };
  const completedOn = async (userId, date) => pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date) VALUES (?, 'completed', ?)`,
    [userId, date],
  );

  await t.test('no active plan and no session today: no workout item', async () => {
    const u = await newUser();
    assert.equal((await routine.readDay(pool, u, MONDAY)).workout, null);
  });

  await t.test('an active plan with no chosen days: every day has one', async () => {
    const u = await newUser();
    await plan(u, 'Push Pull Legs');
    assert.deepEqual((await routine.readDay(pool, u, TUESDAY)).workout,
      { title: 'Push Pull Legs', done: false });
  });

  await t.test('chosen days: present on one, absent on another', async () => {
    const u = await newUser();
    await plan(u);
    await trainingDays(u, [1, 3, 5]);
    assert.deepEqual((await routine.readDay(pool, u, MONDAY)).workout,
      { title: 'Upper Body', done: false });
    assert.equal((await routine.readDay(pool, u, TUESDAY)).workout, null);
  });

  await t.test('a session completed that day makes it done, even on an unchosen day', async () => {
    const u = await newUser();
    await plan(u);
    await trainingDays(u, [1]);
    await completedOn(u, TUESDAY);
    assert.deepEqual((await routine.readDay(pool, u, TUESDAY)).workout,
      { title: 'Upper Body', done: true });
  });

  await t.test('a session completed with no active plan reads "Workout"', async () => {
    const u = await newUser();
    await completedOn(u, MONDAY);
    assert.deepEqual((await routine.readDay(pool, u, MONDAY)).workout,
      { title: 'Workout', done: true });
  });
});
