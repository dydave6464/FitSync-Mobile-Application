'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { resolveCues } = require('../src/db/cues');
const { writePair } = require('../src/db/ai-cues');

/// A service that counts its calls and can be told to fail.
///
/// Counting rather than mocking: the point of every test here is how OFTEN the
/// generator runs, which is what makes a rate-limited free tier affordable.
/// A mock that merely records being called would prove nothing about that.
function countingService({ answer = 'ok' } = {}) {
  const service = {
    calls: 0,
    seen: [],
    model: 'test-model',
    async generate(request) {
      service.calls += 1;
      service.seen.push(request);
      if (answer === 'fail') return null;
      if (answer === 'slow') await new Promise((r) => setTimeout(r, 40));
      return [
        { title: 'Stop at the ribs', detail: 'Past that the joint takes the load.' },
        { title: 'Control the descent', detail: 'Two seconds down.' },
      ];
    },
  };
  return service;
}

test('resolving the cues for an exercise', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('c@example.com','x','C')",
  );
  const userId = u.insertId;

  const [press] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Overhead Press','delts','live')",
  );
  const exerciseId = press.insertId;
  await pool.query(
    'INSERT INTO coaching_cues (exercise_id, order_no, cue_text) VALUES (?, 1, ?)',
    [exerciseId, 'Brace before you press.'],
  );

  const [bare] = await pool.query(
    "INSERT INTO exercises (name, muscle_group, status) VALUES ('Nameless Move','calves','live')",
  );

  async function giveShoulderInjury() {
    const [rows] = await pool.query(
      "SELECT injury_id FROM injuries WHERE name = 'Shoulder'",
    );
    await pool.query(
      'INSERT IGNORE INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [userId, rows[0].injury_id],
    );
    return rows[0].injury_id;
  }

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  // The common case and the reason this feature is affordable: most exercises
  // are not flagged, and they must cost a query and nothing else.
  await t.test('an unflagged exercise returns catalogue cues, calling nothing',
    async () => {
      const service = countingService();
      const result = await resolveCues(pool, service, userId, exerciseId);

      assert.equal(result.source, 'catalogue');
      assert.equal(result.injury, null);
      assert.equal(result.cues.length, 1);
      assert.equal(result.cues[0].title, 'Brace before you press.');
      // One shape for the client either way; a catalogue cue has no second line.
      assert.equal(result.cues[0].detail, null);
      assert.equal(service.calls, 0);
    });

  await t.test('an exercise with no cues at all returns an empty list',
    async () => {
      const service = countingService();
      const result = await resolveCues(pool, service, userId, bare.insertId);

      assert.equal(result.source, 'catalogue');
      assert.deepEqual(result.cues, []);
      assert.equal(service.calls, 0);
    });

  await t.test('a flagged exercise generates once and says what it is for',
    async () => {
      await giveShoulderInjury();
      const service = countingService();

      const result = await resolveCues(pool, service, userId, exerciseId);

      assert.equal(result.source, 'ai');
      assert.equal(result.injury.name, 'Shoulder');
      assert.equal(result.injury.reason, 'trains_region');
      assert.equal(result.cues.length, 2);
      assert.equal(service.calls, 1);

      // The gate's findings have to reach the generator, or the cues are
      // generic and the gate bought nothing.
      assert.equal(service.seen[0].exerciseName, 'Overhead Press');
      assert.equal(service.seen[0].injuryName, 'Shoulder');
      assert.equal(service.seen[0].reason, 'trains_region');
    });

  await t.test('the second request is served from MySQL', async () => {
    const service = countingService();
    const result = await resolveCues(pool, service, userId, exerciseId);

    assert.equal(result.source, 'ai');
    assert.equal(result.cues[0].title, 'Stop at the ribs');
    assert.equal(service.calls, 0, 'a cached pair must not call the generator');
  });

  await t.test('the stored row records the model that wrote it', async () => {
    const [rows] = await pool.query(
      'SELECT order_no, title, detail, model FROM exercise_ai_cues ORDER BY order_no',
    );
    assert.equal(rows.length, 2);
    assert.deepEqual(rows.map((r) => r.order_no), [1, 2]);
    assert.equal(rows[0].model, 'test-model');
    assert.equal(rows[0].title, 'Stop at the ribs');
  });

  // A burst is exactly what a free-tier rate limit refuses, and two screens
  // opening the same exercise at once is the ordinary way to produce one.
  await t.test('two concurrent misses generate once', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    const service = countingService({ answer: 'slow' });

    const [a, b] = await Promise.all([
      resolveCues(pool, service, userId, exerciseId),
      resolveCues(pool, service, userId, exerciseId),
    ]);

    assert.equal(a.source, 'ai');
    assert.equal(b.source, 'ai');
    assert.deepEqual(a.cues, b.cues);
    assert.equal(service.calls, 1);
  });

  // The whole failure contract in one test: nothing thrown, nothing stored,
  // and the user still reads usable cues.
  await t.test('a failed generation falls back and stores nothing', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    const service = countingService({ answer: 'fail' });

    const result = await resolveCues(pool, service, userId, exerciseId);

    assert.equal(result.source, 'catalogue');
    assert.equal(result.cues[0].title, 'Brace before you press.');
    const [stored] = await pool.query('SELECT * FROM exercise_ai_cues');
    assert.equal(stored.length, 0);
  });

  // A failure must not poison the pair: the next attempt tries again.
  await t.test('a later attempt after a failure still generates', async () => {
    const service = countingService();
    const result = await resolveCues(pool, service, userId, exerciseId);

    assert.equal(result.source, 'ai');
    assert.equal(service.calls, 1);
  });

  // Storing is idempotent on uq_eac, so a writer that raced past the
  // single-flight lock overwrites the pair rather than doubling it. Exercised
  // directly: resolveCues would never make this call twice, which is exactly
  // why the guarantee has to be tested where it lives.
  await t.test('writing the same pair twice overwrites rather than doubling',
    async () => {
      const injuryId = await giveShoulderInjury();
      await pool.query('DELETE FROM exercise_ai_cues');

      const first = [
        { title: 'One', detail: 'First detail.' },
        { title: 'Two', detail: 'Second detail.' },
      ];
      const second = [
        { title: 'One revised', detail: 'Rewritten.' },
        { title: 'Two', detail: 'Second detail.' },
      ];

      await writePair(pool, exerciseId, injuryId, first, 'model-a');
      await writePair(pool, exerciseId, injuryId, second, 'model-b');

      const [rows] = await pool.query(
        `SELECT order_no, title, model FROM exercise_ai_cues
          WHERE exercise_id = ? AND injury_id = ? ORDER BY order_no`,
        [exerciseId, injuryId],
      );
      assert.equal(rows.length, 2, 'the pair must not double');
      assert.equal(rows[0].title, 'One revised');
      assert.equal(rows[0].model, 'model-b');
    });

  await t.test('writing an empty set writes nothing at all', async () => {
    const injuryId = await giveShoulderInjury();
    await pool.query('DELETE FROM exercise_ai_cues');

    await writePair(pool, exerciseId, injuryId, [], 'model-a');

    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM exercise_ai_cues');
    assert.equal(Number(rows[0].n), 0);
  });
});
