'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  startSession, getActiveSession, getSessionById, logSet, deleteSet,
  completeSession, abandonSession, lastPerformance, completedThisWeek,
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

  await t.test("completing volume is scoped to its own session, not a user's earlier one", async () => {
    const { userId, exerciseId } = await seed();

    const { session: first } = await startSession(pool, userId);
    await logSet(pool, userId, first.sessionId, { exerciseId, setNumber: 1, weightKg: 10, reps: 10 });
    const doneFirst = await completeSession(pool, userId, first.sessionId, 15);
    // 10*10 = 100 -- left behind as a completed row in set_logs once this
    // session closes.
    assert.strictEqual(doneFirst.totalVolumeKg, 100);

    const { session: second } = await startSession(pool, userId);
    await logSet(pool, userId, second.sessionId, { exerciseId, setNumber: 1, weightKg: 5, reps: 6 });
    const doneSecond = await completeSession(pool, userId, second.sessionId, 20);

    // 5*6 = 30. If the aggregate query were not scoped by session_id, this
    // would also pick up the first session's 100kg row (same user, same
    // exercise, both completed), landing on 130 instead of 30 -- a sum that
    // does not equal either session's true volume, so no coincidental
    // predicate could make this pass by accident.
    assert.strictEqual(doneSecond.totalVolumeKg, 30);
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

    // Same mutate-before-check concern as abandonSession's non-owner guard --
    // a return-value check alone would not catch an UPDATE that ran before
    // the ownership check completed. Confirm the real owner's session is
    // untouched: still in progress, with no duration or volume stamped.
    const reread = await getSessionById(pool, a.userId, session.sessionId);
    assert.equal(reread.status, 'in_progress');
    assert.equal(reread.durationMin, null);
    assert.equal(reread.totalVolumeKg, null);
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

  await t.test('last performance is the heaviest set of the latest completed session', async () => {
    const { userId, exerciseId } = await seed();

    // An older session, heavier -- must lose to the more recent one.
    const older = await startSession(pool, userId);
    await logSet(pool, userId, older.session.sessionId, { exerciseId, setNumber: 1, weightKg: 40, reps: 5 });
    await completeSession(pool, userId, older.session.sessionId, 30);

    // The latest session: 25 is the heaviest set in it, even though set 3 came last.
    const latest = await startSession(pool, userId);
    await logSet(pool, userId, latest.session.sessionId, { exerciseId, setNumber: 1, weightKg: 22.5, reps: 10 });
    await logSet(pool, userId, latest.session.sessionId, { exerciseId, setNumber: 2, weightKg: 25, reps: 8 });
    await logSet(pool, userId, latest.session.sessionId, { exerciseId, setNumber: 3, weightKg: 20, reps: 6 });
    await completeSession(pool, userId, latest.session.sessionId, 45);

    const rows = await lastPerformance(pool, userId, [exerciseId]);
    assert.equal(rows.length, 1);
    assert.strictEqual(rows[0].weightKg, 25);
    assert.strictEqual(rows[0].reps, 8);
    assert.match(rows[0].sessionDate, /^\d{4}-\d{2}-\d{2}$/);
  });

  await t.test('an in-progress session does not count as a last performance', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 30, reps: 10 });

    assert.deepEqual(await lastPerformance(pool, userId, [exerciseId]), []);
  });

  await t.test('never-logged exercises are omitted, not returned as nulls', async () => {
    const { userId, exerciseId } = await seed();
    assert.deepEqual(await lastPerformance(pool, userId, [exerciseId, 999999]), []);
  });

  await t.test('an empty id list queries nothing', async () => {
    const { userId } = await seed();
    assert.deepEqual(await lastPerformance(pool, userId, []), []);
  });

  await t.test("lastPerformance is user-scoped", async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);
    await logSet(pool, a.userId, session.sessionId, { exerciseId: a.exerciseId, setNumber: 1, weightKg: 30, reps: 10 });
    await completeSession(pool, a.userId, session.sessionId, 30);

    // Same exercise id, a different caller: user B's logger must not be
    // prefilled with user A's weight. Dropping `ws2.user_id = ?` from the
    // subquery would leak it straight through.
    assert.deepEqual(await lastPerformance(pool, b.userId, [a.exerciseId]), []);
  });

  await t.test('lastPerformance drops an id past position 50', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 30, reps: 10 });
    await completeSession(pool, userId, session.sessionId, 30);

    // 50 ids that carry no data, followed by the one exercise that does --
    // the cap keeps only the first 50, so the real exercise at position 51
    // never reaches the query and its performance is silently dropped.
    const fillerIds = Array.from({ length: 50 }, (_, i) => 900000 + i);
    const rows = await lastPerformance(pool, userId, [...fillerIds, exerciseId]);
    assert.deepEqual(rows, []);
  });

  await t.test('lastPerformance keeps an id at position 50', async () => {
    const { userId, exerciseId } = await seed();
    const { session } = await startSession(pool, userId);
    await logSet(pool, userId, session.sessionId, { exerciseId, setNumber: 1, weightKg: 30, reps: 10 });
    await completeSession(pool, userId, session.sessionId, 30);

    // Only 49 fillers this time, so the real exercise lands at position 50 --
    // inside the cap. Paired with the position-51 case above, this pins the
    // boundary at exactly 50 rather than merely proving "no more than 50".
    const fillerIds = Array.from({ length: 49 }, (_, i) => 900000 + i);
    const rows = await lastPerformance(pool, userId, [...fillerIds, exerciseId]);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].exerciseId, exerciseId);
    assert.strictEqual(rows[0].weightKg, 30);
  });

  await t.test('the week lists completed session dates only', async () => {
    const { userId } = await seed();

    const done = await startSession(pool, userId);
    await completeSession(pool, userId, done.session.sessionId, 40);

    // An abandoned session must not appear -- placed tomorrow rather than
    // today, so its date survives the `SELECT DISTINCT`. Same-day would
    // collapse into the completed row regardless of the status filter,
    // making the assertion below pass even with that filter deleted.
    const [extra] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'abandoned', DATE_ADD(CURDATE(), INTERVAL 1 DAY))`,
      [userId],
    );
    assert.ok(extra.insertId);

    const dates = await completedThisWeek(pool, userId);
    assert.equal(dates.length, 1);
    assert.match(dates[0], /^\d{4}-\d{2}-\d{2}$/);
  });

  await t.test('last week is outside the window', async () => {
    const { userId } = await seed();
    await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL 14 DAY))`,
      [userId],
    );
    assert.deepEqual(await completedThisWeek(pool, userId), []);
  });

  await t.test('completedThisWeek is user-scoped', async () => {
    const a = await seed();
    const b = await seed();
    const { session } = await startSession(pool, a.userId);
    await completeSession(pool, a.userId, session.sessionId, 30);

    // User A trained today; user B's week strip must stay empty.
    assert.deepEqual(await completedThisWeek(pool, b.userId), []);
  });
});
