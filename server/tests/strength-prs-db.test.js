'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const { countNewPrs } = require('../src/db/strength');

test('new PR count', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [exRows] = await pool.query(
    "SELECT exercise_id FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 2",
  );
  const squat = exRows[0].exercise_id;
  const press = exRows[1].exercise_id;

  let seq = 0;
  const makeUser = async () => {
    seq += 1;
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'P')`,
      [`pr${seq}@example.com`],
    );
    return res.insertId;
  };

  /// One session holding the given sets. Raw SQL: this file is about what the
  /// count REPORTS, not how a workout gets logged.
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

  await t.test('a heavier best than all earlier history counts', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 2, sets: [{ weightKg: 65, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 1);
  });

  await t.test('an exercise counts once however many sets beat its best', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 5, sets: [{ weightKg: 65, reps: 5 }] });
    await session(u, { daysAgo: 2, sets: [{ weightKg: 70, reps: 5 }, { weightKg: 67.5, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 1);
  });

  await t.test('each exercise that beats its own best counts', async () => {
    const u = await makeUser();
    await session(u, {
      daysAgo: 40,
      sets: [{ weightKg: 60, reps: 5 }, { exerciseId: press, weightKg: 40, reps: 5 }],
    });
    await session(u, {
      daysAgo: 2,
      sets: [{ weightKg: 62.5, reps: 5 }, { exerciseId: press, weightKg: 42.5, reps: 5 }],
    });
    assert.equal(await countNewPrs(pool, u, 30), 2);
  });

  await t.test('equalling the earlier best is not a PR', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 2, sets: [{ weightKg: 60, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 0);
  });

  await t.test('an exercise with no earlier history is not a PR', async () => {
    // Otherwise a new account's first month would read as a string of PRs.
    const u = await makeUser();
    await session(u, { daysAgo: 2, sets: [{ weightKg: 100, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 0);
  });

  await t.test('more reps at the same weight is a PR', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 2, sets: [{ weightKg: 60, reps: 8 }] });
    assert.equal(await countNewPrs(pool, u, 30), 1);
  });

  await t.test('sets that cannot carry an estimate are ignored', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    // Each beats 60x5's e1RM of 70 on paper, and none may count:
    await session(u, { daysAgo: 3, sets: [{ weightKg: 50, reps: 20 }] }); // over 12 reps
    await session(u, { daysAgo: 3, sets: [{ weightKg: null, reps: 5 }] }); // unweighted
    await session(u, { daysAgo: 3, sets: [{ weightKg: 90, reps: 5, done: false }] }); // unticked
    await session(u, { daysAgo: 3, status: 'abandoned', sets: [{ weightKg: 90, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 0);
  });

  await t.test("another user's lifts are not counted", async () => {
    const a = await makeUser();
    const b = await makeUser();
    await session(a, { daysAgo: 40, sets: [{ weightKg: 60, reps: 5 }] });
    await session(b, { daysAgo: 2, sets: [{ weightKg: 100, reps: 5 }] });
    assert.equal(await countNewPrs(pool, a, 30), 0);
  });

  await t.test('the window includes its oldest day, as the summary does', async () => {
    const u = await makeUser();
    await session(u, { daysAgo: 31, sets: [{ weightKg: 60, reps: 5 }] });
    await session(u, { daysAgo: 30, sets: [{ weightKg: 65, reps: 5 }] });
    assert.equal(await countNewPrs(pool, u, 30), 1);
  });
});
