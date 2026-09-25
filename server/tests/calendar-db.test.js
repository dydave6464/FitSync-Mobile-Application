'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { readCalendar } = require('../src/db/calendar');

// A fixed today, so weekdays never depend on when the suite runs.
// 2026-09-24 is a Thursday (weekday 4).
const TODAY = '2026-09-24';

test('calendar db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  let seq = 0;
  const newUser = async () => {
    seq += 1;
    const [u] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'C')`,
      [`calendar${seq}@example.com`],
    );
    return u.insertId;
  };

  /// Rows written directly: these tests are about what readCalendar REPORTS.
  const habit = async (userId, {
    title = 'Stretch', time = null, weekdays = [1, 2, 3, 4, 5, 6, 7], active = true,
  } = {}) => {
    const [h] = await pool.query(
      `INSERT INTO routine_habits (user_id, title, scheduled_time, is_active)
       VALUES (?, ?, ?, ?)`,
      [userId, title, time, active],
    );
    for (const d of weekdays) {
      await pool.query(
        'INSERT INTO routine_habit_days (habit_id, weekday) VALUES (?, ?)',
        [h.insertId, d],
      );
    }
    return h.insertId;
  };
  const tick = (habitId, date) => pool.query(
    'INSERT INTO routine_checks (habit_id, check_date) VALUES (?, ?)', [habitId, date],
  );
  const plan = async (userId, name = 'Upper/Lower', active = true) => {
    const [p] = await pool.query(
      `INSERT INTO workout_plans
         (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, ?, 'full_body', 3, 45, ?)`,
      [userId, name, active],
    );
    return p.insertId;
  };
  const trainingDays = async (userId, days) => {
    for (const d of days) {
      await pool.query(
        'INSERT INTO user_training_days (user_id, weekday) VALUES (?, ?)', [userId, d],
      );
    }
  };
  const session = (userId, date, { planId = null, status = 'completed' } = {}) => pool.query(
    `INSERT INTO workout_sessions (user_id, plan_id, status, session_date)
     VALUES (?, ?, ?, ?)`,
    [userId, planId, status, date],
  );
  const read = (userId, from, to) => readCalendar(pool, userId, from, to, TODAY);
  const byDate = (cal) => Object.fromEntries(cal.days.map((d) => [d.date, d]));

  await t.test('one entry per date, oldest first, with the day it was read on', async () => {
    const cal = await read(await newUser(), '2026-09-22', '2026-09-26');
    assert.equal(cal.today, TODAY);
    assert.deepEqual(
      cal.days.map((d) => d.date),
      ['2026-09-22', '2026-09-23', '2026-09-24', '2026-09-25', '2026-09-26'],
    );
    for (const d of cal.days) {
      assert.equal(d.workout, null, d.date);
      assert.deepEqual(d.habits, [], d.date);
    }
  });

  await t.test('a past day shows its workout and its ticks, deleted habits included', async () => {
    const u = await newUser();
    const p = await plan(u, 'Upper/Lower');
    const stretch = await habit(u, { title: 'Stretch', time: '06:30' });
    const old = await habit(u, { title: 'Old', active: false });
    await tick(stretch, '2026-09-22');
    await tick(old, '2026-09-22');
    await session(u, '2026-09-22', { planId: p });

    const day = (await read(u, '2026-09-22', '2026-09-22')).days[0];

    assert.deepEqual(day.workout, { title: 'Upper/Lower', done: true });
    assert.deepEqual(day.habits, [
      { habitId: stretch, title: 'Stretch', time: '06:30', done: true },
      { habitId: old, title: 'Old', time: null, done: true },
    ]);
  });

  await t.test('a past day with nothing done is empty, whatever was scheduled', async () => {
    const u = await newUser();
    await plan(u);                        // no training days chosen: every day
    await habit(u, { title: 'Stretch' }); // every day
    const day = (await read(u, '2026-09-23', '2026-09-23')).days[0];
    assert.equal(day.workout, null);
    assert.deepEqual(day.habits, []);
  });

  await t.test('a past workout is named by its own plan, else "Workout"; unfinished ones do not count', async () => {
    const u = await newUser();
    await plan(u, 'Current');
    const old = await plan(u, 'Old block', false);
    await session(u, '2026-09-20', { planId: old });
    await session(u, '2026-09-21');
    await session(u, '2026-09-22', { status: 'in_progress' });
    await session(u, '2026-09-23', { status: 'abandoned' });

    const days = byDate(await read(u, '2026-09-20', '2026-09-23'));

    assert.deepEqual(days['2026-09-20'].workout, { title: 'Old block', done: true });
    assert.deepEqual(days['2026-09-21'].workout, { title: 'Workout', done: true });
    assert.equal(days['2026-09-22'].workout, null);
    assert.equal(days['2026-09-23'].workout, null);
  });

  await t.test('today lists the habits due with their ticks, plus one ticked though no longer due', async () => {
    const u = await newUser();
    const mobility = await habit(u, { title: 'Mobility', time: '07:00', weekdays: [4] });
    const walk = await habit(u, { title: 'Walk', weekdays: [4] });
    const reading = await habit(u, { title: 'Read', weekdays: [1] }); // ticked, then moved off Thursday
    await habit(u, { title: 'Swim', weekdays: [5] });                 // not today
    await tick(mobility, TODAY);
    await tick(reading, TODAY);

    const day = (await read(u, TODAY, TODAY)).days[0];

    assert.deepEqual(day.habits, [
      { habitId: mobility, title: 'Mobility', time: '07:00', done: true },
      { habitId: reading, title: 'Read', time: null, done: true },
      { habitId: walk, title: 'Walk', time: null, done: false },
    ]);
  });

  await t.test("today's workout: planned on a training day, done once a session is finished", async () => {
    const u = await newUser();
    const p = await plan(u, 'Upper/Lower');
    await trainingDays(u, [4]);
    assert.deepEqual((await read(u, TODAY, TODAY)).days[0].workout,
      { title: 'Upper/Lower', done: false });

    await session(u, TODAY, { planId: p });
    assert.deepEqual((await read(u, TODAY, TODAY)).days[0].workout,
      { title: 'Upper/Lower', done: true });
  });

  await t.test("today's workout: none on an unchosen day, but done whatever the day once finished", async () => {
    const u = await newUser();
    await plan(u, 'Upper/Lower');
    await trainingDays(u, [1]);
    assert.equal((await read(u, TODAY, TODAY)).days[0].workout, null);

    await session(u, TODAY);
    assert.deepEqual((await read(u, TODAY, TODAY)).days[0].workout,
      { title: 'Upper/Lower', done: true });
  });

  await t.test('with no plan, a session finished today reads "Workout"', async () => {
    const u = await newUser();
    await session(u, TODAY);
    assert.deepEqual((await read(u, TODAY, TODAY)).days[0].workout,
      { title: 'Workout', done: true });
  });

  await t.test('future days follow the habit weekdays and the training days, nothing done', async () => {
    const u = await newUser();
    await plan(u, 'Upper/Lower');
    await trainingDays(u, [1, 5]);
    const stretch = await habit(u, { title: 'Stretch', weekdays: [5, 6] });
    await habit(u, { title: 'Old', active: false });
    const stretchDue = { habitId: stretch, title: 'Stretch', time: null, done: false };

    // Fri 25, Sat 26, Sun 27, Mon 28.
    const days = byDate(await read(u, '2026-09-25', '2026-09-28'));

    assert.deepEqual(days['2026-09-25'], {
      date: '2026-09-25', workout: { title: 'Upper/Lower', done: false }, habits: [stretchDue],
    });
    assert.deepEqual(days['2026-09-26'], { date: '2026-09-26', workout: null, habits: [stretchDue] });
    assert.deepEqual(days['2026-09-27'], { date: '2026-09-27', workout: null, habits: [] });
    assert.deepEqual(days['2026-09-28'], {
      date: '2026-09-28', workout: { title: 'Upper/Lower', done: false }, habits: [],
    });
  });

  await t.test('without an active plan, no day from today on has a workout', async () => {
    const u = await newUser();
    await plan(u, 'Shelved', false);
    const cal = await read(u, TODAY, '2026-09-30');
    for (const d of cal.days) assert.equal(d.workout, null, d.date);
  });

  await t.test('a range across a month end keeps counting weekdays', async () => {
    const u = await newUser();
    await habit(u, { title: 'Thursdays', weekdays: [4] });
    const cal = await read(u, '2026-09-29', '2026-10-02');
    assert.deepEqual(
      cal.days.map((d) => d.date),
      ['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'],
    );
    assert.deepEqual(cal.days.map((d) => d.habits.length), [0, 0, 1, 0]);
  });

  await t.test('habits within a day: timed by time, then untimed by title', async () => {
    const u = await newUser();
    await habit(u, { title: 'Zed', time: '21:00' });
    await habit(u, { title: 'Walk' });
    await habit(u, { title: 'Abs', time: '06:00' });
    await habit(u, { title: 'Breathe' });
    const day = (await read(u, '2026-09-25', '2026-09-25')).days[0];
    assert.deepEqual(day.habits.map((h) => h.title), ['Abs', 'Zed', 'Breathe', 'Walk']);
  });

  await t.test("another user's data never appears", async () => {
    const mine = await newUser();
    const theirs = await newUser();
    const p = await plan(theirs);
    const h = await habit(theirs);
    await tick(h, '2026-09-22');
    await tick(h, TODAY);
    await session(theirs, '2026-09-22', { planId: p });

    const cal = await read(mine, '2026-09-22', '2026-09-26');

    for (const d of cal.days) {
      assert.equal(d.workout, null, d.date);
      assert.deepEqual(d.habits, [], d.date);
    }
  });
});
