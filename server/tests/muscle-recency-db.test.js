'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');
const { readMuscleRecency } = require('../src/db/muscle-recency');

test('muscle recency', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  // The fixture's exercises train abs (core), biceps (arms) and quads (legs).
  // Catalogue status is not filtered on: its quads exercise is 'pending', and
  // a logged set trained the muscle whatever the catalogue thinks of it.
  const exerciseFor = async (muscle) => {
    const [[row]] = await pool.query(
      'SELECT exercise_id FROM exercises WHERE muscle_group = ? LIMIT 1',
      [muscle],
    );
    return row.exercise_id;
  };
  const core = await exerciseFor('abs');
  const arms = await exerciseFor('biceps');
  const legs = await exerciseFor('quads');

  let seq = 0;
  const makeUser = async () => {
    seq += 1;
    const [res] = await pool.query(
      `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'M')`,
      [`muscle${seq}@example.com`],
    );
    return res.insertId;
  };

  /// One session [daysAgo] holding one set of each exercise given. Raw SQL:
  /// this file is about what is READ, not how a workout is logged.
  const trained = async (userId, daysAgo, exerciseIds, { status = 'completed', done = true, weightKg = 20 } = {}) => {
    const [s] = await pool.query(
      `INSERT INTO workout_sessions (user_id, status, session_date)
       VALUES (?, ?, DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
      [userId, status, daysAgo],
    );
    let n = 0;
    for (const exerciseId of exerciseIds) {
      n += 1;
      await pool.query(
        `INSERT INTO set_logs (session_id, exercise_id, set_number, weight_kg, reps, is_completed)
         VALUES (?, ?, ?, ?, 10, ?)`,
        [s.insertId, exerciseId, n, weightKg, done],
      );
    }
  };

  const ago = async (n) => {
    const [[{ d }]] = await pool.query(
      `SELECT DATE_FORMAT(CURDATE() - INTERVAL ? DAY, '%Y-%m-%d') AS d`, [n],
    );
    return d;
  };

  await t.test('a new account has six groups, none trained, in body order', async () => {
    const groups = await readMuscleRecency(pool, await makeUser());
    assert.deepEqual(groups, [
      { group: 'chest', lastTrained: null, daysAgo: null },
      { group: 'back', lastTrained: null, daysAgo: null },
      { group: 'shoulders', lastTrained: null, daysAgo: null },
      { group: 'arms', lastTrained: null, daysAgo: null },
      { group: 'legs', lastTrained: null, daysAgo: null },
      { group: 'core', lastTrained: null, daysAgo: null },
    ]);
  });

  await t.test('untrained groups first, then the longest rested', async () => {
    const u = await makeUser();
    await trained(u, 1, [core]);
    await trained(u, 5, [legs]);
    await trained(u, 3, [arms]);

    const groups = await readMuscleRecency(pool, u);

    assert.deepEqual(groups.map((g) => g.group),
      ['chest', 'back', 'shoulders', 'legs', 'arms', 'core']);
    assert.deepEqual(groups[3], { group: 'legs', lastTrained: await ago(5), daysAgo: 5 });
    assert.deepEqual(groups[5], { group: 'core', lastTrained: await ago(1), daysAgo: 1 });
  });

  await t.test("a group's date is its most recent workout", async () => {
    const u = await makeUser();
    await trained(u, 9, [legs]);
    await trained(u, 2, [legs]);
    const legsRow = (await readMuscleRecency(pool, u)).find((g) => g.group === 'legs');
    assert.equal(legsRow.daysAgo, 2);
  });

  await t.test('a bodyweight set counts; an unticked set or unfinished workout does not', async () => {
    const u = await makeUser();
    await trained(u, 4, [core], { weightKg: null });
    await trained(u, 1, [core], { done: false });
    await trained(u, 0, [arms], { status: 'abandoned' });
    await trained(u, 0, [legs], { status: 'in_progress' });

    const byGroup = Object.fromEntries((await readMuscleRecency(pool, u)).map((g) => [g.group, g]));

    assert.equal(byGroup.core.daysAgo, 4, 'bodyweight counts; the unticked set does not');
    assert.equal(byGroup.arms.daysAgo, null);
    assert.equal(byGroup.legs.daysAgo, null);
  });

  await t.test("another user's training is not yours", async () => {
    const u = await makeUser();
    const other = await makeUser();
    await trained(other, 0, [core, arms, legs]);
    assert.ok((await readMuscleRecency(pool, u)).every((g) => g.daysAgo === null));
  });

  await t.test('ties go by body order', async () => {
    const u = await makeUser();
    await trained(u, 2, [core, arms]);
    const trainedGroups = (await readMuscleRecency(pool, u)).filter((g) => g.daysAgo !== null);
    assert.deepEqual(trainedGroups.map((g) => g.group), ['arms', 'core']);
  });
});
