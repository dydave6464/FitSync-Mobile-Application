'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  startSession, getActiveSession, getSessionById, logSet, deleteSet,
  completeSession, abandonSession,
} = require('../src/db/sessions');

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

  await t.test('a set is stored and read back as numbers, not strings', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);

    const stored = await logSet(pool, userId, session.sessionId, {
      exerciseId, setNumber: 1, weightKg: 22.5, reps: 10,
    });
    assert.deepEqual(stored, { exerciseId, setNumber: 1, weightKg: 22.5, reps: 10 });

    const reread = await getActiveSession(pool, userId);
    assert.equal(reread.sets.length, 1);
    // Not '22.50'. DECIMAL comes out of mysql2 as a string.
    assert.strictEqual(reread.sets[0].weightKg, 22.5);
    assert.strictEqual(reread.sets[0].reps, 10);
  });

  await t.test('logging the same set twice updates it rather than duplicating', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);

    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 20, reps: 10 });
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 25, reps: 8 });

    const reread = await getActiveSession(pool, userId);
    assert.equal(reread.sets.length, 1);
    assert.equal(reread.sets[0].weightKg, 25);
    assert.equal(reread.sets[0].reps, 8);
  });

  await t.test('a bodyweight set with no weight and no reps still counts', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);

    await logSet(pool, userId, session.sessionId, {
      exerciseId, setNumber: 1, weightKg: null, reps: null,
    });

    const reread = await getActiveSession(pool, userId);
    assert.equal(reread.sets.length, 1);
    assert.equal(reread.sets[0].weightKg, null);
    assert.equal(reread.sets[0].reps, null);
  });

  await t.test('a set for an exercise outside the plan is rejected', async () => {
    const { userId } = await seed();
    const [other] = await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES (CONCAT('Ex ', UUID()), 'chest', 'live')",
    );
    const { session } = await startSession(pool, userId);

    await assert.rejects(
      logSet(pool, userId, session.sessionId, {
        exerciseId: other.insertId, setNumber: 1, weightKg: 10, reps: 10,
      }),
      (err) => err.code === 'EXERCISE_NOT_IN_PLAN' && err.status === 400,
    );
  });

  await t.test("logging into another user's session returns null", async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);

    const result = await logSet(pool, b.userId, session.sessionId, {
      exerciseId: b.exerciseId, setNumber: 1, weightKg: 10, reps: 10,
    });
    assert.equal(result, null);
  });

  await t.test("deleting from another user's session returns false and leaves the row", async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);
    await logSet(pool, a.userId, session.sessionId, {
      exerciseId: a.exerciseId, setNumber: 1, weightKg: 20, reps: 10,
    });

    const result = await deleteSet(pool, b.userId, session.sessionId, a.exerciseId, 1);
    assert.equal(result, false);

    // The guard being tested is `if (!session) return false;` -- proving the
    // call returns false is not enough on its own, since a DELETE that ran
    // and simply matched nothing would also return false. The row must
    // still be there, read back as its actual owner.
    const reread = await getSessionById(pool, a.userId, session.sessionId);
    assert.deepEqual(reread.sets, [{
      exerciseId: a.exerciseId, setNumber: 1, weightKg: 20, reps: 10,
    }]);
  });

  await t.test('un-ticking removes the row, and doing it twice is not an error', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 20, reps: 10 });

    assert.equal(await deleteSet(pool, userId, session.sessionId, exerciseId, 1), true);
    assert.deepEqual((await getActiveSession(pool, userId)).sets, []);
    assert.equal(await deleteSet(pool, userId, session.sessionId, exerciseId, 1), true);
  });

  await t.test('logSet on a closed session throws SESSION_NOT_IN_PROGRESS', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await pool.query(
      "UPDATE workout_sessions SET status = 'completed' WHERE session_id = ?",
      [session.sessionId],
    );

    await assert.rejects(
      logSet(pool, userId, session.sessionId, {
        exerciseId, setNumber: 1, weightKg: 10, reps: 10,
      }),
      (err) => err.code === 'SESSION_NOT_IN_PROGRESS' && err.status === 409,
    );
  });

  await t.test('deleteSet on a closed session throws SESSION_NOT_IN_PROGRESS', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 20, reps: 10 });
    await pool.query(
      "UPDATE workout_sessions SET status = 'abandoned' WHERE session_id = ?",
      [session.sessionId],
    );

    await assert.rejects(
      deleteSet(pool, userId, session.sessionId, exerciseId, 1),
      (err) => err.code === 'SESSION_NOT_IN_PROGRESS' && err.status === 409,
    );
  });

  await t.test('completing stamps duration and a server-computed volume', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 20, reps: 10 });
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 2, weightKg: 22.5, reps: 8 });

    const done = await completeSession(pool, userId, session.sessionId, 47);

    assert.equal(done.status, 'completed');
    assert.equal(done.durationMin, 47);
    // 20*10 + 22.5*8 = 380
    assert.strictEqual(done.totalVolumeKg, 380);
    assert.equal(await getActiveSession(pool, userId), null);
  });

  await t.test('a bodyweight-only session completes with zero volume', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: null, reps: 15 });

    const done = await completeSession(pool, userId, session.sessionId, 20);
    assert.strictEqual(done.totalVolumeKg, 0);
  });

  await t.test('completing twice is a conflict', async () => {
    const { userId } = await seed();
    const { session } = await startSession(pool, userId);
    await completeSession(pool, userId, session.sessionId, 30);

    await assert.rejects(
      completeSession(pool, userId, session.sessionId, 30),
      (err) => err.code === 'SESSION_NOT_IN_PROGRESS' && err.status === 409,
    );
  });

  await t.test("completing another user's session returns null", async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);
    assert.equal(await completeSession(pool, b.userId, session.sessionId, 30), null);
  });

  await t.test('abandoning closes the session without recording volume', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 20, reps: 10 });

    assert.equal(await abandonSession(pool, userId, session.sessionId), true);

    const closed = await getSessionById(pool, userId, session.sessionId);
    assert.equal(closed.status, 'abandoned');
    assert.equal(closed.totalVolumeKg, null);
    assert.equal(await getActiveSession(pool, userId), null);
  });

  await t.test("abandoning another user's session returns false and leaves the status unchanged", async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);

    assert.equal(await abandonSession(pool, b.userId, session.sessionId), false);

    // The guard being tested is `if (!session) return false;` -- a return-value
    // check alone would still pass if the UPDATE ran before that check was
    // reached. The session must still be the real owner's, read back as
    // still in progress.
    const reread = await getSessionById(pool, a.userId, session.sessionId);
    assert.equal(reread.status, 'in_progress');
  });

  await t.test('abandoning an already-closed session throws SESSION_NOT_IN_PROGRESS', async () => {
    const { userId } = await seed();
    const { session } = await startSession(pool, userId);
    await abandonSession(pool, userId, session.sessionId);

    await assert.rejects(
      abandonSession(pool, userId, session.sessionId),
      (err) => err.code === 'SESSION_NOT_IN_PROGRESS' && err.status === 409,
    );
  });
});
