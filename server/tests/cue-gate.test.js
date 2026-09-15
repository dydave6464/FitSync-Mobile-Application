'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { flagFor } = require('../src/db/cue-gate');

async function injuryId(pool, name) {
  const [rows] = await pool.query(
    'SELECT injury_id FROM injuries WHERE name = ?', [name],
  );
  return rows[0].injury_id;
}

async function addExercise(pool, name, muscleGroup) {
  const [r] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES (?, ?, 'live')",
    [name, muscleGroup],
  );
  return r.insertId;
}

test('the cue gate', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('g@example.com','x','G')",
  );
  const userId = u.insertId;

  // 'delts' is in INJURY_MUSCLE_GROUPS.upper_body, which Shoulder belongs to.
  // 'calves' is in lower_body, which it does not.
  const press = await addExercise(pool, 'Overhead Press', 'delts');
  const calf = await addExercise(pool, 'Standing Calf Raise', 'calves');

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // The common case, and the one that has to cost nothing: most users have no
  // injuries and every exercise they open must resolve without a service call.
  await t.test('a user with no injuries flags nothing', async () => {
    assert.equal(await flagFor(pool, userId, press), null);
  });

  await t.test('an exercise that trains the injured region is flagged',
    async () => {
      const shoulder = await injuryId(pool, 'Shoulder');
      await pool.query(
        'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
        [userId, shoulder],
      );

      const flag = await flagFor(pool, userId, press);
      assert.equal(flag.injuryId, shoulder);
      assert.equal(flag.injuryName, 'Shoulder');
      assert.equal(flag.reason, 'trains_region');
    });

  await t.test('an exercise that trains nothing injured is not flagged',
    async () => {
      assert.equal(await flagFor(pool, userId, calf), null);
    });

  // The precise instrument. A contraindication is a claim about THIS exercise
  // and THIS joint and carries the reason why, where a region overlap is only
  // a claim about a muscle group.
  await t.test('a contraindication outranks a region overlap', async () => {
    const shoulder = await injuryId(pool, 'Shoulder');
    await pool.query(
      `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern)
       VALUES (?, ?, ?)`,
      [press, shoulder, 'shoulder_load'],
    );

    const flag = await flagFor(pool, userId, press);
    assert.equal(flag.reason, 'shoulder_load');
  });

  // A contraindication for an injury whose region the exercise does NOT train
  // still flags -- that is the whole reason the contraindication table exists
  // (muscle_group records what a movement TRAINS, not what it LOADS).
  await t.test('a contraindication flags an exercise no region rule would',
    async () => {
      const wrist = await injuryId(pool, 'Wrist');
      await pool.query(
        'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
        [userId, wrist],
      );
      await pool.query(
        `INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern)
         VALUES (?, ?, ?)`,
        [calf, wrist, 'wrist_load'],
      );

      const flag = await flagFor(pool, userId, calf);
      assert.equal(flag.injuryName, 'Wrist');
      assert.equal(flag.reason, 'wrist_load');
    });

  // The cache is keyed on ONE injury_id, so a repeated call must resolve to
  // the same one or the same pair writes two different rows.
  await t.test('several matching injuries resolve the same way every time',
    async () => {
      const elbow = await injuryId(pool, 'Elbow');
      await pool.query(
        'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
        [userId, elbow],
      );

      const first = await flagFor(pool, userId, press);
      const second = await flagFor(pool, userId, press);
      assert.deepEqual(first, second);
      // Shoulder is contraindicated for the press; Elbow only overlaps it.
      assert.equal(first.reason, 'shoulder_load');
    });

  // The tie-break the cache key rests on. Two injuries that BOTH merely
  // overlap must not pick differently from one call to the next, so the rule
  // is "lowest injury_id" -- arbitrary, but stable. seed-injuries.js inserts
  // Shoulder before Elbow, so Shoulder holds the lower id.
  await t.test('two overlapping injuries resolve to the lowest id', async () => {
    const curl = await addExercise(pool, 'Dumbbell Curl', 'biceps');
    const shoulder = await injuryId(pool, 'Shoulder');
    const elbow = await injuryId(pool, 'Elbow');
    assert.ok(shoulder < elbow, 'fixture assumption: Shoulder seeded first');

    // 'biceps' is upper_body, which both injuries belong to, and neither is
    // contraindicated for this exercise -- so only the tie-break decides.
    const flag = await flagFor(pool, userId, curl);
    assert.equal(flag.reason, 'trains_region');
    assert.equal(flag.injuryId, shoulder);
  });

  await t.test('an exercise that does not exist flags nothing', async () => {
    assert.equal(await flagFor(pool, userId, 999999), null);
  });
});
