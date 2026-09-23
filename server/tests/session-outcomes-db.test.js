'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const {
  pendingOutcome, recordOutcome, OUTCOME_WINDOW_DAYS,
} = require('../src/db/session-outcomes');

test('session outcomes db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const [knee] = await pool.query("SELECT injury_id FROM injuries WHERE name = 'Knee'");
  const kneeId = knee[0].injury_id;

  const newUser = async () => {
    const [u] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES (CONCAT('u', UUID(), '@b.com'), 'x', 'U')",
    );
    return u.insertId;
  };

  // A session `daysAgo` days back. Raw SQL: this file is about outcomes, and
  // how a session comes to be completed is sessions-db.test.js's business.
  const session = async (userId, { daysAgo = 1, status = 'completed' } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, ?, CURDATE() - INTERVAL ? DAY)`,
      [userId, status, daysAgo],
    );
    return s.insertId;
  };

  const insertOutcome = (userId, sessionId, painLevel, injuryId) => pool.query(
    `INSERT INTO session_outcomes (user_id, session_id, pain_level, injury_id)
     VALUES (?, ?, ?, ?)`,
    [userId, sessionId, painLevel, injuryId],
  );

  await t.test('a region alongside no pain is refused by the table itself', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await assert.rejects(
      () => insertOutcome(userId, sessionId, 'none', kneeId),
      (err) => err.code === 'ER_CHECK_CONSTRAINT_VIOLATED',
    );
  });

  await t.test('pain without a region is refused by the table itself', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await assert.rejects(
      () => insertOutcome(userId, sessionId, 'mild', null),
      (err) => err.code === 'ER_CHECK_CONSTRAINT_VIOLATED',
    );
  });

  await t.test('a session holds at most one report', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await insertOutcome(userId, sessionId, 'none', null);
    await assert.rejects(
      () => insertOutcome(userId, sessionId, 'mild', kneeId),
      (err) => err.code === 'ER_DUP_ENTRY',
    );
  });

  await t.test('a report goes when its session does', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await insertOutcome(userId, sessionId, 'moderate', kneeId);

    await pool.query('DELETE FROM workout_sessions WHERE session_id = ?', [sessionId]);

    const [rows] = await pool.query(
      'SELECT outcome_id FROM session_outcomes WHERE session_id = ?', [sessionId],
    );
    assert.equal(rows.length, 0,
      'a pain report about a deleted session has nothing left to train on');
  });

  await t.test('the last session is pending while it is unanswered and recent', async () => {
    const userId = await newUser();
    await session(userId, { daysAgo: 3 });
    const latest = await session(userId, { daysAgo: 1 });

    const pending = await pendingOutcome(pool, userId);

    assert.equal(pending.sessionId, latest);
    assert.match(pending.sessionDate, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(pending.planName, null);
  });

  await t.test('the window is seven days, inclusive', async () => {
    assert.equal(OUTCOME_WINDOW_DAYS, 7);
    const edge = await newUser();
    const onEdge = await session(edge, { daysAgo: 7 });
    assert.equal((await pendingOutcome(pool, edge)).sessionId, onEdge);

    const stale = await newUser();
    await session(stale, { daysAgo: 8 });
    assert.equal(await pendingOutcome(pool, stale), null,
      'pain today is not evidence about a session more than a week ago');
  });

  await t.test('nothing is pending once the last session is answered', async () => {
    const userId = await newUser();
    const latest = await session(userId);
    await recordOutcome(pool, userId, latest, { painLevel: 'none', injuryId: null });
    assert.equal(await pendingOutcome(pool, userId), null);
  });

  await t.test('an older unanswered session is never asked about', async () => {
    const userId = await newUser();
    await session(userId, { daysAgo: 4 }); // dismissed, never answered
    const latest = await session(userId, { daysAgo: 1 });
    await recordOutcome(pool, userId, latest, { painLevel: 'none', injuryId: null });

    assert.equal(await pendingOutcome(pool, userId), null,
      'the question is about LAST session; an earlier one would pin pain on the wrong cause');
  });

  await t.test('nothing is pending without a completed session', async () => {
    const fresh = await newUser();
    assert.equal(await pendingOutcome(pool, fresh), null);

    const unfinished = await newUser();
    await session(unfinished, { status: 'in_progress', daysAgo: 0 });
    await session(unfinished, { status: 'abandoned', daysAgo: 1 });
    assert.equal(await pendingOutcome(pool, unfinished), null);
  });

  await t.test('an abandoned session never displaces the completed one before it', async () => {
    const userId = await newUser();
    const completed = await session(userId, { daysAgo: 2 });
    await session(userId, { status: 'abandoned', daysAgo: 1 });
    assert.equal((await pendingOutcome(pool, userId)).sessionId, completed);
  });

  await t.test('records no pain without a region', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);

    const outcome = await recordOutcome(pool, userId, sessionId, { painLevel: 'none', injuryId: null });

    assert.deepEqual(
      { ...outcome, outcomeId: typeof outcome.outcomeId },
      { outcomeId: 'number', sessionId, painLevel: 'none', injuryId: null },
    );
    const [rows] = await pool.query(
      'SELECT user_id, pain_level, injury_id FROM session_outcomes WHERE session_id = ?', [sessionId],
    );
    assert.deepEqual({ ...rows[0] }, { user_id: userId, pain_level: 'none', injury_id: null });
  });

  await t.test('records pain with its region', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);

    const outcome = await recordOutcome(pool, userId, sessionId, { painLevel: 'severe', injuryId: kneeId });

    assert.equal(outcome.painLevel, 'severe');
    assert.equal(outcome.injuryId, kneeId);
  });

  await t.test("another user's session is not found", async () => {
    const owner = await newUser();
    const intruder = await newUser();
    const sessionId = await session(owner);

    assert.equal(
      await recordOutcome(pool, intruder, sessionId, { painLevel: 'none', injuryId: null }),
      null,
    );
    const [rows] = await pool.query('SELECT outcome_id FROM session_outcomes WHERE session_id = ?', [sessionId]);
    assert.equal(rows.length, 0);
  });

  await t.test('a session that is not completed is not found', async () => {
    const userId = await newUser();
    const open = await session(userId, { status: 'in_progress', daysAgo: 0 });
    assert.equal(
      await recordOutcome(pool, userId, open, { painLevel: 'none', injuryId: null }),
      null,
    );
  });

  await t.test('an unknown region is a bad request', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await assert.rejects(
      () => recordOutcome(pool, userId, sessionId, { painLevel: 'mild', injuryId: 999999 }),
      (err) => err.status === 400 && err.code === 'INJURY_INVALID',
    );
  });

  await t.test('a second answer is a conflict and the first one stands', async () => {
    const userId = await newUser();
    const sessionId = await session(userId);
    await recordOutcome(pool, userId, sessionId, { painLevel: 'mild', injuryId: kneeId });

    await assert.rejects(
      () => recordOutcome(pool, userId, sessionId, { painLevel: 'none', injuryId: null }),
      (err) => err.status === 409 && err.code === 'OUTCOME_EXISTS',
    );
    const [rows] = await pool.query('SELECT pain_level FROM session_outcomes WHERE session_id = ?', [sessionId]);
    assert.deepEqual(rows.map((r) => r.pain_level), ['mild']);
  });
});
