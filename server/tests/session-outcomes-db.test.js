'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');

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
});
