'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { createStorage } = require('../src/services/storage');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('session history', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const app = buildTestApp({
    pool, storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const [exRows] = await pool.query("SELECT exercise_id FROM exercises WHERE status='live' LIMIT 2");
  const exerciseId = exRows[0].exercise_id;

  const freshUser = async (email) => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { token: login.body.data.token, userId: res.body.data.user.userId };
  };

  /// Writes a finished session directly. Raw SQL on purpose: driving the real
  /// start/log/complete flow would make every assertion here depend on three
  /// other endpoints, and this file is about what history REPORTS.
  const writeSession = async (userId, {
    status = 'completed',
    date,
    daysAgo = 0,
    volume = 1000,
    minutes = 45,
    planName = null,
    sets = 3,
    exercises = 2,
  } = {}) => {
    let planId = null;
    if (planName) {
      const [plan] = await pool.query(
        `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
         VALUES (?, ?, 'full_body', 3, 45, FALSE)`,
        [userId, planName],
      );
      planId = plan.insertId;
      for (let i = 0; i < exercises; i += 1) {
        await pool.query(
          `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
           VALUES (?, ?, ?, 3, '8-12')`,
          [planId, exerciseId, i + 1],
        );
      }
    }
    const when = date || `DATE_SUB(CURDATE(), INTERVAL ${daysAgo} DAY)`;
    const [s] = await pool.query(
      `INSERT INTO workout_sessions
         (user_id, plan_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, ?, ?, ${date ? '?' : when}, NOW(), ?, ?)`,
      date
        ? [userId, planId, status, date, minutes, volume]
        : [userId, planId, status, minutes, volume],
    );
    if (!planName) {
      for (let i = 0; i < exercises; i += 1) {
        await pool.query(
          'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, ?)',
          [s.insertId, exRows[i % exRows.length].exercise_id, i + 1],
        );
      }
    }
    for (let i = 0; i < sets; i += 1) {
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps)
         VALUES (?, ?, ?, 20, 10)`,
        [s.insertId, exerciseId, i + 1],
      );
    }
    return s.insertId;
  };

  const history = async (token, query = '') => {
    const res = await request(app).get(`/api/v1/sessions${query}`)
      .set('Authorization', `Bearer ${token}`).expect(200);
    return res.body.data;
  };

  const summary = async (token, period) => {
    const res = await request(app)
      .get(`/api/v1/sessions/summary${period ? `?period=${period}` : ''}`)
      .set('Authorization', `Bearer ${token}`).expect(200);
    return res.body.data.summary;
  };

  await t.test('lists a completed session with what it was worth', async () => {
    const u = await freshUser('h1@example.com');
    await writeSession(u.userId, { volume: 2953, minutes: 2, sets: 21, exercises: 2 });

    const { sessions } = await history(u.token);
    assert.equal(sessions.length, 1);
    assert.equal(sessions[0].totalVolumeKg, 2953);
    assert.equal(sessions[0].durationMin, 2);
    assert.equal(sessions[0].setCount, 21);
    assert.equal(sessions[0].exerciseCount, 2);
  });

  await t.test('a session with no plan reports none', async () => {
    // What lets the client call it "Your own workout" rather than borrowing
    // the name of a plan it was never part of.
    const u = await freshUser('h2@example.com');
    await writeSession(u.userId);

    const { sessions } = await history(u.token);
    assert.equal(sessions[0].planName, null);
  });

  await t.test('a plan session carries the plan name it was run from', async () => {
    // The name is read at query time, not derived from the ACTIVE plan: a
    // session run six weeks ago belongs to whatever plan was current then,
    // and regenerating since must not rewrite its history.
    const u = await freshUser('h3@example.com');
    await writeSession(u.userId, { planName: 'Upper Body · Push' });

    const { sessions } = await history(u.token);
    assert.equal(sessions[0].planName, 'Upper Body · Push');
  });

  await t.test('an unfinished session is not history', async () => {
    // in_progress is the workout you are in; abandoned is one you threw away.
    // Neither is something you did.
    const u = await freshUser('h4@example.com');
    await writeSession(u.userId, { status: 'in_progress' });
    await writeSession(u.userId, { status: 'abandoned' });
    await writeSession(u.userId, { status: 'completed' });

    const { sessions, total } = await history(u.token);
    assert.equal(sessions.length, 1);
    assert.equal(total, 1);
  });

  await t.test('the newest session is first', async () => {
    const u = await freshUser('h5@example.com');
    await writeSession(u.userId, { daysAgo: 9, volume: 100 });
    await writeSession(u.userId, { daysAgo: 0, volume: 300 });
    await writeSession(u.userId, { daysAgo: 4, volume: 200 });

    const { sessions } = await history(u.token);
    assert.deepEqual(sessions.map((s) => s.totalVolumeKg), [300, 200, 100]);
  });

  await t.test('another account\'s sessions are not yours', async () => {
    const mine = await freshUser('h6@example.com');
    const theirs = await freshUser('h7@example.com');
    await writeSession(theirs.userId, { volume: 9999 });

    const { sessions, total } = await history(mine.token);
    assert.equal(sessions.length, 0);
    assert.equal(total, 0);
  });

  await t.test('history pages', async () => {
    const u = await freshUser('h8@example.com');
    for (let i = 0; i < 3; i += 1) await writeSession(u.userId, { daysAgo: i, volume: 100 * (3 - i) });

    const first = await history(u.token, '?page=1&limit=2');
    assert.equal(first.sessions.length, 2);
    assert.equal(first.total, 3);
    assert.equal(first.page, 1);

    const second = await history(u.token, '?page=2&limit=2');
    assert.equal(second.sessions.length, 1);
    assert.equal(second.sessions[0].totalVolumeKg, 100, 'the oldest is last');
  });

  await t.test('summary adds up what was done this week', async () => {
    const u = await freshUser('h9@example.com');
    await writeSession(u.userId, { daysAgo: 0, volume: 1000, sets: 10 });
    await writeSession(u.userId, { daysAgo: 1, volume: 500, sets: 4 });

    const s = await summary(u.token, 'week');
    assert.equal(s.sessionCount, 2);
    assert.equal(s.totalVolumeKg, 1500);
    assert.equal(s.setCount, 14);
  });

  await t.test('a session outside the window is outside the summary', async () => {
    const u = await freshUser('h10@example.com');
    await writeSession(u.userId, { daysAgo: 0, volume: 1000, sets: 10 });
    await writeSession(u.userId, { daysAgo: 300, volume: 7777, sets: 99 });

    const week = await summary(u.token, 'week');
    assert.equal(week.sessionCount, 1);
    assert.equal(week.totalVolumeKg, 1000);

    const year = await summary(u.token, 'year');
    assert.equal(year.sessionCount, 2, 'a year reaches back further than a week');
    assert.equal(year.totalVolumeKg, 8777);
  });

  await t.test('an abandoned session counts for nothing', async () => {
    const u = await freshUser('h11@example.com');
    await writeSession(u.userId, { status: 'abandoned', volume: 5000, sets: 50 });

    const s = await summary(u.token, 'week');
    assert.equal(s.sessionCount, 0);
    assert.equal(s.totalVolumeKg, 0);
    assert.equal(s.setCount, 0);
  });

  await t.test('no history summarises as zero, not as an error', async () => {
    // The state a new account is in, and the one that sent a user looking for
    // a bug: it has to be plainly readable as "nothing yet".
    const u = await freshUser('h12@example.com');

    const s = await summary(u.token, 'week');
    assert.deepEqual(s, { sessionCount: 0, setCount: 0, totalVolumeKg: 0, newPrCount: 0 });
  });

  await t.test('summary counts the window\'s new PRs', async () => {
    const u = await freshUser('h12pr@example.com');
    await writeSession(u.userId, { daysAgo: 40, sets: 1 }); // 20 x 10
    const recent = await writeSession(u.userId, { daysAgo: 2, sets: 0 });
    await pool.query(
      `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
       VALUES (?, ?, 1, 30, 10, TRUE)`,
      [recent, exerciseId],
    );
    await pool.query('UPDATE set_logs SET is_completed = TRUE WHERE session_id IN (SELECT session_id FROM workout_sessions WHERE user_id = ?)', [u.userId]);

    const s = await summary(u.token, 'month');
    assert.equal(s.newPrCount, 1);
  });

  await t.test('an unknown period is refused rather than guessed', async () => {
    const u = await freshUser('h13@example.com');
    const res = await request(app).get('/api/v1/sessions/summary?period=fortnight')
      .set('Authorization', `Bearer ${u.token}`).expect(400);
    assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
  });

  // 'constructor' is not a period, but it IS a property of every object's
  // prototype. A bare SUMMARY_WINDOWS[period] hands back a function, which is
  // truthy, so the unknown-period guard passes it through and it reaches the
  // query as a bind parameter -- a 500 where this 400 belongs.
  await t.test('a prototype property is not mistaken for a period', async () => {
    const u = await freshUser('h14@example.com');
    for (const period of ['constructor', 'toString', '__proto__']) {
      const res = await request(app).get(`/api/v1/sessions/summary?period=${period}`)
        .set('Authorization', `Bearer ${u.token}`).expect(400);
      assert.equal(res.body.error.code, 'INVALID_QUERY_PARAM');
    }
  });

  await t.test('history needs a signed-in caller', async () => {
    await request(app).get('/api/v1/sessions').expect(401);
    await request(app).get('/api/v1/sessions/summary').expect(401);
  });
});

test('the last completed workout, for repeating', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));

  const app = buildTestApp({
    pool, storage: createStorage({ mode: 'local', localDir: 'storage' }),
  });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const [live] = await pool.query(
    "SELECT exercise_id, name FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 3",
  );

  const freshUser = async (email) => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'W' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { token: login.body.data.token, userId: res.body.data.user.userId };
  };

  const last = async (token) => {
    const res = await request(app).get('/api/v1/sessions/last')
      .set('Authorization', `Bearer ${token}`).expect(200);
    return res.body.data.session;
  };

  /// A hand-picked session: owns its list in session_exercises.
  const manualSession = async (userId, exerciseIds, { daysAgo = 0, status = 'completed' } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY), NOW(), 30, 500)`,
      [userId, status, daysAgo],
    );
    for (const [i, id] of exerciseIds.entries()) {
      await pool.query(
        'INSERT INTO session_exercises (session_id, exercise_id, order_no) VALUES (?, ?, ?)',
        [s.insertId, id, i + 1],
      );
    }
    return s.insertId;
  };

  /// A plan-backed session: borrows the plan's rows for its rotation day.
  const planSession = async (userId, exerciseIds, { dayNo = 1, daysAgo = 0 } = {}) => {
    const [plan] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, 'Upper Body · Push', 'push_pull_legs', 3, 45, FALSE)`,
      [userId],
    );
    for (const [i, id] of exerciseIds.entries()) {
      await pool.query(
        `INSERT INTO plan_exercises (plan_id, exercise_id, day_no, order_no, target_sets, target_reps)
         VALUES (?, ?, ?, ?, 3, '8-12')`,
        [plan.insertId, id, dayNo, i + 1],
      );
    }
    // A different day nobody trained, to prove the day is respected.
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, day_no, order_no, target_sets, target_reps)
       VALUES (?, ?, ?, 9, 3, '8-12')`,
      [plan.insertId, live[2].exercise_id, dayNo + 1],
    );
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, plan_id, plan_day_no, status, session_date, started_at, duration_min, total_volume_kg)
       VALUES (?, ?, ?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY), NOW(), 40, 900)`,
      [userId, plan.insertId, dayNo, daysAgo],
    );
    return s.insertId;
  };

  await t.test('a hand-picked workout comes back with its own list', async () => {
    const u = await freshUser('l1@example.com');
    await manualSession(u.userId, [live[0].exercise_id, live[1].exercise_id]);

    const session = await last(u.token);
    assert.equal(session.planName, null);
    assert.deepEqual(session.exercises.map((e) => e.exerciseId),
      [live[0].exercise_id, live[1].exercise_id]);
  });

  await t.test('the list keeps the order it was trained in', async () => {
    const u = await freshUser('l2@example.com');
    await manualSession(u.userId, [live[1].exercise_id, live[0].exercise_id]);

    const session = await last(u.token);
    assert.deepEqual(session.exercises.map((e) => e.exerciseId),
      [live[1].exercise_id, live[0].exercise_id],
      'repeating a workout in a different order is a different workout');
  });

  await t.test('each exercise carries what the picker needs to draw it', async () => {
    // The review screen renders name, muscle group and equipment. Ids alone
    // would leave it showing blank rows for a workout the user recognises.
    const u = await freshUser('l3@example.com');
    await manualSession(u.userId, [live[0].exercise_id]);

    const only = (await last(u.token)).exercises[0];
    assert.equal(typeof only.name, 'string');
    assert.ok(only.name.length > 0);
    assert.ok('muscleGroup' in only);
    assert.ok('equipment' in only);
    assert.ok('thumbnailUrl' in only);
  });

  await t.test('a plan workout comes back with that day\'s exercises', async () => {
    // session_exercises is empty for a plan session by design, so the list has
    // to be derived from the plan -- and from the rotation day it trained,
    // not from the whole plan.
    const u = await freshUser('l4@example.com');
    await planSession(u.userId, [live[0].exercise_id, live[1].exercise_id], { dayNo: 2 });

    const session = await last(u.token);
    assert.equal(session.planName, 'Upper Body · Push');
    assert.deepEqual(session.exercises.map((e) => e.exerciseId),
      [live[0].exercise_id, live[1].exercise_id]);
  });

  await t.test('the newest completed workout is the one returned', async () => {
    const u = await freshUser('l5@example.com');
    await manualSession(u.userId, [live[0].exercise_id], { daysAgo: 5 });
    await manualSession(u.userId, [live[1].exercise_id], { daysAgo: 0 });

    const session = await last(u.token);
    assert.deepEqual(session.exercises.map((e) => e.exerciseId), [live[1].exercise_id]);
  });

  await t.test('an abandoned workout is not something to repeat', async () => {
    const u = await freshUser('l6@example.com');
    await manualSession(u.userId, [live[0].exercise_id], { status: 'abandoned' });

    assert.equal(await last(u.token), null);
  });

  await t.test('an untrained account has nothing to repeat', async () => {
    // Null rather than 404: having trained nothing is the normal state a new
    // account is in, the same contract GET /sessions/active states.
    const u = await freshUser('l7@example.com');
    assert.equal(await last(u.token), null);
  });

  await t.test('another account\'s workout is not yours to repeat', async () => {
    const mine = await freshUser('l8@example.com');
    const theirs = await freshUser('l9@example.com');
    await manualSession(theirs.userId, [live[0].exercise_id]);

    assert.equal(await last(mine.token), null);
  });

  await t.test('an exercise no longer live is dropped, not repeated', async () => {
    // Exercises are never deleted -- set_logs holds a RESTRICT key to them --
    // so one leaves the catalogue by being demoted back to 'pending'. A
    // workout can be months old, and refusing the whole repeat because one
    // movement was demoted leaves the user no way to do the rest of it.
    const u = await freshUser('l10@example.com');
    await manualSession(u.userId, [live[0].exercise_id, live[1].exercise_id]);
    await pool.query("UPDATE exercises SET status='pending' WHERE exercise_id = ?",
      [live[0].exercise_id]);

    const session = await last(u.token);
    assert.deepEqual(session.exercises.map((e) => e.exerciseId), [live[1].exercise_id]);

    await pool.query("UPDATE exercises SET status='live' WHERE exercise_id = ?",
      [live[0].exercise_id]);
  });

  await t.test('a workout with no live exercise left is not repeatable', async () => {
    const u = await freshUser('l11@example.com');
    await manualSession(u.userId, [live[0].exercise_id]);
    await pool.query("UPDATE exercises SET status='pending' WHERE exercise_id = ?",
      [live[0].exercise_id]);

    // Null, not an empty list: a workout of no exercises is not a workout,
    // and the sheet must not offer to repeat nothing.
    assert.equal(await last(u.token), null);

    await pool.query("UPDATE exercises SET status='live' WHERE exercise_id = ?",
      [live[0].exercise_id]);
  });

  await t.test('repeating needs a signed-in caller', async () => {
    await request(app).get('/api/v1/sessions/last').expect(401);
  });
});
