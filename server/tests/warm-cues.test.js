'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { createCueService } = require('../src/services/cues');
const { warmCues } = require('../scripts/warm-cues');

function countingService({ answer = 'ok' } = {}) {
  const service = {
    calls: 0,
    model: 'test-model',
    async generate() {
      service.calls += 1;
      if (answer === 'fail') return null;
      return [
        { title: 'Stop at the ribs', detail: 'Past that the joint takes the load.' },
        { title: 'Control the descent', detail: 'Two seconds down.' },
      ];
    },
  };
  return service;
}

test('warming the cue cache', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('w@example.com','x','W')",
  );
  const userId = u.insertId;

  const [shoulder] = await pool.query(
    "SELECT injury_id FROM injuries WHERE name = 'Shoulder'",
  );
  await pool.query(
    'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
    [userId, shoulder[0].injury_id],
  );

  // 'delts' is upper_body, which Shoulder belongs to. 'calves' is not.
  const [press] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Overhead Press','delts','live')",
  );
  const [calf] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Calf Raise','calves','live')",
  );

  const [plan] = await pool.query(
    `INSERT INTO workout_plans (user_id, name, split_style, days_per_week, session_length_min)
     VALUES (?, 'Demo', 'full_body', 3, 45)`,
    [userId],
  );
  for (const [index, id] of [press.insertId, calf.insertId].entries()) {
    await pool.query(
      `INSERT INTO plan_exercises (plan_id, exercise_id, order_no, target_sets, target_reps)
       VALUES (?, ?, ?, 3, '8-12')`,
      [plan.insertId, id, index + 1],
    );
  }

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // The whole point: it pays for the exercises that will actually show AI
  // cues, and not one more.
  await t.test('fills only the flagged exercises in the active plan',
    async () => {
      const service = countingService();
      const result = await warmCues(pool, service, { userId });

      assert.equal(result.filled, 1, 'only the delt exercise loads the shoulder');
      assert.equal(result.failed, 0);
      assert.equal(service.calls, 1, 'the calf raise must cost nothing');

      const [rows] = await pool.query(
        'SELECT DISTINCT exercise_id FROM exercise_ai_cues',
      );
      assert.equal(rows.length, 1);
      assert.equal(rows[0].exercise_id, press.insertId);
    });

  // Running it again before a demo must not re-buy what it already has.
  await t.test('a second run fills nothing and says so', async () => {
    const service = countingService();
    const result = await warmCues(pool, service, { userId });

    assert.equal(result.filled, 0);
    assert.equal(result.skipped, 1);
    assert.equal(service.calls, 0);
  });

  await t.test('a failed generation is counted, not thrown', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    const service = countingService({ answer: 'fail' });

    const result = await warmCues(pool, service, { userId });

    assert.equal(result.filled, 0);
    assert.equal(result.failed, 1);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM exercise_ai_cues');
    assert.equal(Number(rows[0].n), 0);
  });

  await t.test('a user with no injuries warms nothing', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    await pool.query('DELETE FROM user_injuries WHERE user_id = ?', [userId]);
    const service = countingService();

    const result = await warmCues(pool, service, { userId });

    assert.equal(result.filled, 0);
    assert.equal(result.skipped, 0);
    assert.equal(service.calls, 0);
  });

  // An inactive plan is not what the user is training, so warming it would buy
  // cues for screens nobody is about to open.
  await t.test('an inactive plan is not warmed', async () => {
    await pool.query(
      'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [userId, shoulder[0].injury_id],
    );
    await pool.query('UPDATE workout_plans SET is_active = FALSE WHERE plan_id = ?',
      [plan.insertId]);
    const service = countingService();

    const result = await warmCues(pool, service, { userId });

    assert.equal(result.filled, 0);
    assert.equal(service.calls, 0);

    await pool.query('UPDATE workout_plans SET is_active = TRUE WHERE plan_id = ?',
      [plan.insertId]);
  });

  // The script is what a defence runs beforehand; it has to work against the
  // real service factory, not only against a double.
  await t.test('runs against the stub service end to end', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    const result = await warmCues(pool, createCueService({}), { userId });

    assert.equal(result.filled, 1);
    const [rows] = await pool.query(
      'SELECT title, model FROM exercise_ai_cues ORDER BY order_no',
    );
    assert.match(rows[0].title, /Shoulder/);
    assert.equal(rows[0].model, 'stub');
  });
});
