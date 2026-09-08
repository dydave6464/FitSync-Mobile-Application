'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { startSession, getActiveSession, getSessionById } = require('../src/db/sessions');

test('session db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // A user, an exercise, an active plan containing that exercise.
  const seed = async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    const [e] = await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES (CONCAT('Ex ', UUID()), 'legs', 'live')",
    );
    const [p] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min)
       VALUES (?, 'Plan', 'full_body', 3, 45)`,
      [u.insertId],
    );
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, 1, 3, '8-12')`,
      [p.insertId, e.insertId],
    );
    return { userId: u.insertId, exerciseId: e.insertId, planId: p.insertId };
  };

  await t.test('no active session for a fresh user', async () => {
    const { userId } = await seed();
    assert.equal(await getActiveSession(pool, userId), null);
  });

  await t.test('starting creates one in-progress session against the active plan', async () => {
    const { userId, planId } = await seed();
    const { session, created } = await startSession(pool, userId);

    assert.equal(created, true);
    assert.equal(session.status, 'in_progress');
    assert.equal(session.planId, planId);
    assert.deepEqual(session.sets, []);
    assert.match(session.sessionDate, /^\d{4}-\d{2}-\d{2}$/);
    assert.ok(session.startedAt, 'startedAt is stamped');
  });

  await t.test('starting twice returns the same session, not a second one', async () => {
    const { userId } = await seed();
    const first = await startSession(pool, userId);
    const second = await startSession(pool, userId);

    assert.equal(second.created, false);
    assert.equal(second.session.sessionId, first.session.sessionId);

    const [rows] = await pool.query(
      'SELECT COUNT(*) AS n FROM workout_sessions WHERE user_id = ?',
      [userId],
    );
    assert.equal(rows[0].n, 1);
  });

  await t.test('starting without an active plan is a conflict', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    await assert.rejects(
      startSession(pool, u.insertId),
      (err) => err.code === 'NO_ACTIVE_PLAN' && err.status === 409,
    );
  });

  await t.test("one user's session is invisible to another", async () => {
    const a = await seed();
    const b = await seed();
    await startSession(pool, a.userId);
    assert.equal(await getActiveSession(pool, b.userId), null);
  });

  await t.test('getSessionById returns null for a session id that does not exist', async () => {
    const { userId } = await seed();
    assert.equal(await getSessionById(pool, userId, 999999), null);
  });

  await t.test('getSessionById is invisible to a non-owner but visible to the owner', async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);

    assert.equal(await getSessionById(pool, b.userId, session.sessionId), null);

    const own = await getSessionById(pool, a.userId, session.sessionId);
    assert.equal(own.sessionId, session.sessionId);
  });

  await t.test('starting picks the active plan even when a newer plan is inactive', async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    const [activePlan] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min)
       VALUES (?, 'Active Plan', 'full_body', 3, 45)`,
      [u.insertId],
    );
    const [inactivePlan] = await pool.query(
      `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min, is_active)
       VALUES (?, 'Inactive Plan', 'full_body', 3, 45, FALSE)`,
      [u.insertId],
    );
    assert.ok(inactivePlan.insertId > activePlan.insertId, 'inactive plan has the higher id');

    const { session } = await startSession(pool, u.insertId);
    assert.equal(session.planId, activePlan.insertId);
  });
});
