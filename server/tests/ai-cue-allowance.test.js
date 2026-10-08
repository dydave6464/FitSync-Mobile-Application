'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const { resolveCues } = require('../src/db/cues');
const { FREE_DAILY_AI_CUES } = require('../src/db/ai-cue-allowance');

function countingService({ answer = 'ok' } = {}) {
  const service = {
    calls: 0,
    model: 'test-model',
    async generate() {
      service.calls += 1;
      if (answer === 'fail') return null;
      return [{ title: 'Keep the elbows soft', detail: 'Stop short of pain.' }];
    },
  };
  return service;
}

test('the free AI-cue allowance', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [[shoulder]] = await pool.query("SELECT injury_id FROM injuries WHERE name = 'Shoulder'");
  let seq = 0;
  const newUser = async ({ premium = false } = {}) => {
    seq += 1;
    const [u] = await pool.query(
      'INSERT INTO users (email, password_hash, full_name, is_premium) VALUES (?, ?, ?, ?)',
      [`a${seq}@example.com`, 'x', 'A', premium ? 1 : 0],
    );
    await pool.query('INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)',
      [u.insertId, shoulder.injury_id]);
    return u.insertId;
  };
  // Four delts exercises: all flagged for Shoulder, each with a catalogue cue.
  const presses = [];
  for (const name of ['Press A', 'Press B', 'Press C', 'Press D']) {
    const [r] = await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES (?, 'delts', 'live')", [name],
    );
    await pool.query(
      'INSERT INTO coaching_cues (exercise_id, order_no, cue_text) VALUES (?, 1, ?)',
      [r.insertId, `Catalogue cue for ${name}`],
    );
    presses.push(r.insertId);
  }
  const usesOf = async (userId) => {
    const [[row]] = await pool.query(
      'SELECT COUNT(*) AS n FROM ai_cue_uses WHERE user_id = ?', [userId],
    );
    return Number(row.n);
  };

  await t.test('the limit is three', () => {
    assert.equal(FREE_DAILY_AI_CUES, 3);
  });

  await t.test('a free user gets AI cues on three exercises, then the standard steps', async () => {
    const userId = await newUser();
    const service = countingService();
    for (const id of presses.slice(0, 3)) {
      const r = await resolveCues(pool, service, userId, id);
      assert.equal(r.source, 'ai');
      assert.equal(r.notice, null);
    }
    const fourth = await resolveCues(pool, service, userId, presses[3]);
    assert.equal(fourth.source, 'catalogue');
    assert.equal(fourth.notice, 'free_limit');
    assert.equal(fourth.injury.name, 'Shoulder');
    assert.deepEqual(fourth.cues.map((c) => c.title), ['Catalogue cue for Press D']);
    assert.equal(service.calls, 3, 'the fourth is not generated');
    assert.equal(await usesOf(userId), 3);

    // Re-opening one already counted today is still AI, and counts nothing new.
    const again = await resolveCues(pool, service, userId, presses[0]);
    assert.equal(again.source, 'ai');
    assert.equal(await usesOf(userId), 3);
  });

  await t.test("yesterday's uses do not count today", async () => {
    const userId = await newUser();
    const service = countingService();
    for (const id of presses.slice(0, 3)) await resolveCues(pool, service, userId, id);
    await pool.query(
      'UPDATE ai_cue_uses SET used_on = CURDATE() - INTERVAL 1 DAY WHERE user_id = ?', [userId],
    );
    const r = await resolveCues(pool, service, userId, presses[3]);
    assert.equal(r.source, 'ai');
  });

  await t.test('a Pro user is unlimited and never counted', async () => {
    const userId = await newUser({ premium: true });
    const service = countingService();
    for (const id of presses) {
      const r = await resolveCues(pool, service, userId, id);
      assert.equal(r.source, 'ai');
    }
    assert.equal(await usesOf(userId), 0);
  });

  await t.test('a failed generation answers unavailable and uses nothing', async () => {
    await pool.query('DELETE FROM exercise_ai_cues');
    const userId = await newUser();
    const r = await resolveCues(pool, countingService({ answer: 'fail' }), userId, presses[0]);
    assert.equal(r.source, 'catalogue');
    assert.equal(r.notice, 'unavailable');
    assert.equal(r.injury.name, 'Shoulder');
    assert.equal(await usesOf(userId), 0);
  });

  await t.test('an unflagged exercise has no injury and no notice', async () => {
    const [r] = await pool.query(
      "INSERT INTO exercises (name, muscle_group, status) VALUES ('Calf Move', 'calves', 'live')",
    );
    const userId = await newUser();
    const out = await resolveCues(pool, countingService(), userId, r.insertId);
    assert.equal(out.source, 'catalogue');
    assert.equal(out.injury, null);
    assert.equal(out.notice, null);
  });
});
