'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  seedExercisePreferences, PREFERENCES, nothingMatched,
} = require('../src/db/seed-exercise-preferences');

test('the preference list is well formed', () => {
  assert.equal(PREFERENCES.length, 1170);
  assert.equal(new Set(PREFERENCES.map((p) => p.sourceId)).size, PREFERENCES.length);
  for (const p of PREFERENCES) {
    assert.ok(['first', 'alternative', 'search_only', 'never'].includes(p.priority), p.sourceId);
    assert.equal(typeof p.beginnerFriendly, 'boolean');
  }
  assert.equal(PREFERENCES.filter((p) => p.beginnerFriendly).length, 219);
});

test('a run that matched nothing in the catalogue is reported as a failure', () => {
  // Run before `npm run seed`, every sourceId is unknown and nothing is
  // written -- and every beginner plan is then refused.
  const message = nothingMatched({ skippedUnknown: 1170, total: 1170 });
  assert.match(message, /none of the 1170 exercise preferences matched the catalogue/i);
  assert.match(message, /npm run seed/);
  assert.equal(nothingMatched({ skippedUnknown: 1169, total: 1170 }), null);
  assert.equal(nothingMatched({ skippedUnknown: 0, total: 0 }), null);
});

test('exercise preference seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  // Two catalogue rows the list knows -- sourceId '0493' incline push-up
  // (first, beginner-friendly) and '1273' clap push up (never) -- and one it
  // does not ('9999').
  const ins = (sourceId, name) => pool.query(
    "INSERT INTO exercises (source_id, name, muscle_group, status) VALUES (?, ?, 'pectorals', 'live')",
    [sourceId, name],
  ).then(([r]) => r.insertId);
  await ins('0493', 'incline push-up');
  const clap = await ins('1273', 'clap push up');
  const unknown = await ins('9999', 'not in the list');

  const marks = async () => {
    const [rows] = await pool.query(
      `SELECT x.source_id, p.priority, p.beginner_friendly
         FROM exercise_preferences p JOIN exercises x USING (exercise_id)
        ORDER BY x.source_id`,
    );
    return rows.map((r) => [r.source_id, r.priority, r.beginner_friendly]);
  };

  await t.test('writes the marks by source id and skips exercises not in the catalogue', async () => {
    const s = await seedExercisePreferences(testDbConfig());
    assert.deepEqual(s, {
      inserted: 2, updated: 0, unchanged: 0, skippedUnknown: 1168, manual: 0, total: 1170,
    });
    assert.deepEqual(await marks(), [['0493', 'first', 1], ['1273', 'never', 0]]);
    const [none] = await pool.query('SELECT 1 FROM exercise_preferences WHERE exercise_id = ?', [unknown]);
    assert.equal(none.length, 0, 'an exercise the list does not know stays unmarked');
  });

  await t.test('a re-run changes nothing', async () => {
    const s = await seedExercisePreferences(testDbConfig());
    assert.equal(s.inserted, 0);
    assert.equal(s.updated, 0);
    assert.equal(s.unchanged, 2);
    assert.deepEqual(await marks(), [['0493', 'first', 1], ['1273', 'never', 0]]);
  });

  await t.test('a drifted row is put back to the list', async () => {
    await pool.query(
      "UPDATE exercise_preferences SET priority = 'first', beginner_friendly = TRUE WHERE exercise_id = ?",
      [clap],
    );
    const s = await seedExercisePreferences(testDbConfig());
    assert.equal(s.updated, 1);
    assert.equal(s.unchanged, 1);
    assert.deepEqual(await marks(), [['0493', 'first', 1], ['1273', 'never', 0]]);
  });

  await t.test('an is_manual row is never overwritten', async () => {
    await pool.query(
      "UPDATE exercise_preferences SET priority = 'alternative', beginner_friendly = TRUE, is_manual = 1 WHERE exercise_id = ?",
      [clap],
    );
    const s = await seedExercisePreferences(testDbConfig());
    assert.equal(s.manual, 1);
    assert.equal(s.updated, 0);
    assert.equal(s.unchanged, 1);
    assert.deepEqual(await marks(), [['0493', 'first', 1], ['1273', 'alternative', 1]]);
  });

  await t.test('deleting an exercise removes its mark', async () => {
    await pool.query('DELETE FROM exercises WHERE exercise_id = ?', [clap]);
    assert.deepEqual(await marks(), [['0493', 'first', 1]]);
  });
});
