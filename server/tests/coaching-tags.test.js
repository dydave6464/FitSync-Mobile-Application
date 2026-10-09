'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { flagFor, flagsFor } = require('../src/db/cue-gate');
const { savePlan, getActivePlan } = require('../src/db/plans');
const { startSession, getActiveSession } = require('../src/db/sessions');

async function injuryId(pool, name) {
  const [rows] = await pool.query('SELECT injury_id FROM injuries WHERE name = ?', [name]);
  return rows[0].injury_id;
}

async function addExercise(pool, name, muscleGroup) {
  const [r] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES (?, ?, 'live')",
    [name, muscleGroup],
  );
  return r.insertId;
}

test('coaching tags', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('tag@example.com','x','T')",
  );
  const userId = u.insertId;

  // delts -> upper_body (Shoulder); calves -> lower_body (Knee); squat is
  // quads (lower_body) and also contraindicated for Knee.
  const press = await addExercise(pool, 'Overhead Press', 'delts');
  const calf = await addExercise(pool, 'Standing Calf Raise', 'calves');
  const squat = await addExercise(pool, 'Back Squat', 'quads');
  const knee = await injuryId(pool, 'Knee');
  const shoulder = await injuryId(pool, 'Shoulder');
  await pool.query(
    "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern) VALUES (?, ?, 'knee_load')",
    [squat, knee],
  );

  const setInjuries = async (...ids) => {
    await pool.query('DELETE FROM user_injuries WHERE user_id = ?', [userId]);
    for (const id of ids) {
      await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)', [userId, id]);
    }
  };

  await t.test('flagsFor agrees with flagFor for every exercise', async () => {
    for (const injuries of [[], [shoulder], [knee], [shoulder, knee]]) {
      await setInjuries(...injuries);
      const many = await flagsFor(pool, userId, [press, calf, squat, press]);
      for (const id of [press, calf, squat]) {
        assert.deepEqual(many.get(id) ?? null, await flagFor(pool, userId, id),
          `exercise ${id} with injuries ${injuries}`);
      }
    }
  });

  await t.test('flagsFor with no ids asks nothing and returns an empty map', async () => {
    const flags = await flagsFor(pool, userId, []);
    assert.equal(flags.size, 0);
  });

  await t.test('the active plan tags exactly the coached exercises, live', async () => {
    await setInjuries(shoulder);
    await savePlan(pool, userId, {
      name: 'Tag Plan', splitStyle: 'full_body', daysPerWeek: 3,
      sessionLengthMin: 45, weekNo: 1,
      exercises: [
        { name: 'Overhead Press', dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12' },
        { name: 'Standing Calf Raise', dayNo: 1, orderNo: 2, targetSets: 3, targetReps: '8-12' },
      ],
    });
    let plan = await getActivePlan(pool, userId);
    const byName = (p) => Object.fromEntries(p.exercises.map((e) => [e.name, e.coaching]));
    assert.deepEqual(byName(plan), {
      'Overhead Press': { injuryId: shoulder, injuryName: 'Shoulder' },
      'Standing Calf Raise': null,
    });

    // Computed on read: changing injuries re-tags the same plan, no rebuild.
    await setInjuries(knee);
    plan = await getActivePlan(pool, userId);
    assert.deepEqual(byName(plan), {
      'Overhead Press': null,
      'Standing Calf Raise': { injuryId: knee, injuryName: 'Knee' },
    });

    await setInjuries();
    plan = await getActivePlan(pool, userId);
    assert.deepEqual(byName(plan), { 'Overhead Press': null, 'Standing Calf Raise': null });
  });

  await t.test('a hand-picked session tags its exercises the same way', async () => {
    await setInjuries(knee);
    await startSession(pool, userId, [squat, press]);
    const session = await getActiveSession(pool, userId);
    const tags = Object.fromEntries(session.exercises.map((e) => [e.name, e.coaching]));
    assert.deepEqual(tags, {
      'Back Squat': { injuryId: knee, injuryName: 'Knee' },
      'Overhead Press': null,
    });
  });
});
