'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const goals = require('../src/db/goals');

test('goals db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [exRows] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 3",
  );
  const [squat, press, row] = exRows.map((r) => r.exercise_id);

  let seq = 0;
  const makeUser = async () => {
    seq += 1;
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'G')`,
      [`goal${seq}@example.com`],
    );
    return res.insertId;
  };

  const ago = async (n) => {
    const [[{ d }]] = await pool.query(
      `SELECT DATE_FORMAT(CURDATE() - INTERVAL ? DAY, '%Y-%m-%d') AS d`, [n],
    );
    return d;
  };

  /// One session holding the given sets. Raw SQL: this file is about what
  /// goals REPORT, not how a workout gets logged.
  const session = async (userId, { daysAgo, status = 'completed', sets }) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
      [userId, status, daysAgo],
    );
    let n = 0;
    for (const set of sets) {
      n += 1;
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [s.insertId, set.exerciseId ?? squat, n, set.weightKg, set.reps, set.done ?? true],
      );
    }
  };

  const goal = async (userId, exerciseId, targetKg) =>
    (await goals.createGoal(pool, userId, exerciseId, targetKg)).goalId;

  await t.test('best and reached date come from counting sets only', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 20, sets: [{ weightKg: 50, reps: 5 }] });
    await session(u, { daysAgo: 10, sets: [{ weightKg: 60, reps: 1 }] });
    await session(u, { daysAgo: 5, sets: [{ weightKg: 62.5, reps: 3 }] });
    await session(u, { daysAgo: 3, sets: [{ weightKg: 100, reps: 5, done: false }] });
    await session(u, { daysAgo: 2, status: 'abandoned', sets: [{ weightKg: 90, reps: 5 }] });
    await session(u, { daysAgo: 1, sets: [{ weightKg: 95, reps: 0 }] });

    const g = await goals.readGoal(pool, u, await goal(u, squat, 60));

    assert.equal(g.targetKg, 60);
    assert.equal(g.bestKg, 62.5);
    assert.equal(g.reachedOn, await ago(10));
    assert.equal(g.exerciseId, squat);
    assert.equal(typeof g.exerciseName, 'string');
    assert.deepEqual(Object.keys(g).sort(),
      ['bestKg', 'exerciseId', 'exerciseName', 'goalId', 'reachedOn', 'targetKg']);
  });

  await t.test('a lift never logged has no best and is not reached', async () => {
    const u = await makeUser();
    const g = await goals.readGoal(pool, u, await goal(u, press, 40));
    assert.equal(g.bestKg, null);
    assert.equal(g.reachedOn, null);
  });

  await t.test("another user's sets do not count", async () => {
    const u = await makeUser();
    const other = await makeUser();
    await session(other, { daysAgo: 1, sets: [{ weightKg: 100, reps: 5 }] });
    const g = await goals.readGoal(pool, u, await goal(u, squat, 60));
    assert.equal(g.bestKg, null);
  });

  await t.test('the list puts unreached goals first, newest first, then reached, latest first', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 10, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 4, sets: [{ exerciseId: press, weightKg: 40, reps: 5 }] });
    const reachedEarlier = await goal(u, squat, 55);
    const reachedLater = await goal(u, press, 35);
    const open1 = await goal(u, squat, 100);
    const open2 = await goal(u, row, 50);

    const ids = (await goals.listGoals(pool, u)).map((g) => g.goalId);

    assert.deepEqual(ids, [open2, open1, reachedLater, reachedEarlier]);
  });

  await t.test("deleting removes only the owner's goal", async () => {
    const u = await makeUser();
    const other = await makeUser();
    const id = await goal(u, squat, 70);
    assert.equal(await goals.deleteGoal(pool, other, id), false);
    assert.equal(await goals.deleteGoal(pool, u, id), true);
    assert.equal(await goals.readGoal(pool, u, id), null);
  });

  await t.test('options list lifted exercises, most sets first, with each best', async () => {
    const u = await makeUser();
    await session(u, {
      daysAgo: 3,
      sets: [
        { exerciseId: press, weightKg: 40, reps: 5 },
        { exerciseId: press, weightKg: 42.5, reps: 5 },
        { weightKg: 80, reps: 5 },
        { exerciseId: row, weightKg: 70, reps: 5, done: false },
      ],
    });

    const opts = await goals.listOptions(pool, u);

    assert.deepEqual(opts.map((o) => [o.exerciseId, o.bestKg, o.sets]), [[press, 42.5, 2], [squat, 80, 1]]);
    assert.equal(typeof opts[0].name, 'string');
  });

  await t.test('bestKg and isLiveExercise', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 1, sets: [{ weightKg: 77.5, reps: 2 }] });
    assert.equal(await goals.bestKg(pool, u, squat), 77.5);
    assert.equal(await goals.bestKg(pool, u, press), null);
    assert.equal(await goals.isLiveExercise(pool, squat), true);
    assert.equal(await goals.isLiveExercise(pool, 99999999), false);
  });
});
