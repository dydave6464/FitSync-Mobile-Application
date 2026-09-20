'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { readTrainingLoad, MAX_LOAD } = require('../src/db/training-load');

/// Inserts a finished session `daysAgo` days back carrying `volumeKg`.
async function logSession(pool, userId, daysAgo, volumeKg) {
  await pool.query(
    `INSERT INTO workout_sessions (user_id, session_date, status, total_volume_kg)
     VALUES (?, DATE_SUB(CURDATE(), INTERVAL ? DAY), 'completed', ?)`,
    [userId, daysAgo, volumeKg],
  );
}

async function freshUser(pool, email) {
  const [res] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name)
     VALUES (?, 'x', 'Test User')`,
    [email],
  );
  return res.insertId;
}

/// risk.py's own numbers, read out of the file rather than copied into it.
///
/// The index has no meaning apart from the estimator that consumes it, so the
/// calibration below has to score with the real thresholds. Reading them means
/// a threshold moving in Python fails this test, instead of quietly leaving it
/// asserting a calibration nobody ships any more.
function riskConstants() {
  const source = fs.readFileSync(
    path.join(__dirname, '..', '..', 'ml', 'app', 'risk.py'),
    'utf8',
  );

  function constant(name) {
    const match = source.match(new RegExp(`^${name}\\s*=\\s*([0-9.]+)`, 'm'));
    assert.ok(match, `${name} not found in risk.py`);
    return Number(match[1]);
  }

  function scale(name) {
    const match = source.match(new RegExp(`^${name}\\s*=\\s*\\{([^}]*)\\}`, 'm'));
    assert.ok(match, `${name} not found in risk.py`);
    const table = {};
    for (const [, key, value] of match[1].matchAll(/"([a-z_]+)":\s*([0-9.]+)/g)) {
      table[key] = Number(value);
    }
    assert.ok(Object.keys(table).length > 0, `${name} parsed empty`);
    return table;
  }

  const divisor = source.match(/max\(payload\.load,\s*0\.0\)\s*\/\s*([0-9.]+)/);
  assert.ok(divisor, "risk.py's load term not found");

  return {
    loadDivisor: Number(divisor[1]),
    moderateAt: constant('MODERATE_AT'),
    highAt: constant('HIGH_AT'),
    sleep: scale('SLEEP'),
    soreness: scale('SORENESS'),
    energy: scale('ENERGY'),
    stress: scale('STRESS'),
  };
}

/// risk.py's `estimate`, in JavaScript: the load term, the mean recovery
/// penalty, the clamp, then the two thresholds.
function riskLevelFor(k, load, checkins) {
  let score = Math.max(load, 0) / k.loadDivisor;
  if (checkins.length > 0) {
    const penalties = checkins.map((c) => (
      (k.sleep[c.sleepQuality] ?? 0)
      + (k.soreness[c.muscleSoreness] ?? 0)
      + (k.energy[c.energy] ?? 0)
      + (k.stress[c.stress] ?? 0)
    ));
    score += penalties.reduce((a, b) => a + b, 0) / penalties.length;
  }
  score = Math.min(Math.max(score, 0), 100);

  if (score >= k.highAt) return 'high';
  if (score >= k.moderateAt) return 'moderate';
  return 'low';
}

test('training load index', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('an account with no history scores zero', async () => {
    const userId = await freshUser(pool, 'load-none@example.com');
    assert.equal(await readTrainingLoad(pool, userId), 0);
  });

  await t.test('training at the usual rate scores zero', async () => {
    const userId = await freshUser(pool, 'load-steady@example.com');
    // 1000kg in each of the last four weeks, including this one.
    for (const daysAgo of [1, 8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    // The index is the excess over the user's own baseline, so training
    // exactly as usual is no excess at all -- not the midpoint of the scale.
    assert.equal(await readTrainingLoad(pool, userId), 0);
  });

  await t.test('training less than usual floors at zero', async () => {
    const userId = await freshUser(pool, 'load-easy@example.com');
    for (const daysAgo of [8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    await logSession(pool, userId, 1, 400); // a deload week
    assert.equal(await readTrainingLoad(pool, userId), 0);
  });

  await t.test('a spike scores the excess over baseline', async () => {
    const userId = await freshUser(pool, 'load-build@example.com');
    for (const daysAgo of [8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    await logSession(pool, userId, 1, 1500); // 150% of baseline
    assert.equal(await readTrainingLoad(pool, userId), 50);
  });

  await t.test('the baseline is the three weeks before this one', async () => {
    const userId = await freshUser(pool, 'load-window@example.com');
    // Deliberately uneven, and chosen so every plausible wrong window gives a
    // different answer: the correct baseline is 1200/3 = 400 a week, so 600
    // this week is 150% of it and scores 50. Folding this week in would make
    // the average 450 and the answer 33.33; dividing the same three weeks by
    // four would make it 300 and the answer 100.
    await logSession(pool, userId, 8, 700);
    await logSession(pool, userId, 15, 300);
    await logSession(pool, userId, 22, 200);
    await logSession(pool, userId, 1, 600);
    assert.equal(await readTrainingLoad(pool, userId), 50);
  });

  await t.test('an enormous spike is clamped', async () => {
    const userId = await freshUser(pool, 'load-spike@example.com');
    await logSession(pool, userId, 22, 100);   // a quiet baseline week
    await logSession(pool, userId, 1, 100000); // then an enormous week
    assert.equal(await readTrainingLoad(pool, userId), 130);
    assert.equal(MAX_LOAD, 130);
  });
});

/// What the index actually reports about a person, end to end.
///
/// The numbers above are arithmetic; these are the claims the design makes --
/// an ordinary week reads `low`, and no single signal on its own reaches
/// `high`. Nothing pinned those before, which is how an index centred on 100
/// shipped against an estimator that halves it and calls 40 moderate: every
/// healthy user read `moderate`.
test('training load calibration', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const k = riskConstants();
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('a steady week and a decent morning read low', async () => {
    const userId = await freshUser(pool, 'cal-steady@example.com');
    for (const daysAgo of [1, 8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    const load = await readTrainingLoad(pool, userId);
    const level = riskLevelFor(k, load, [{
      sleepQuality: 'good',
      muscleSoreness: 'none',
      energy: 'high',
      stress: 'very_low',
    }]);
    assert.equal(level, 'low', `load ${load} should not alarm anyone`);
  });

  await t.test('building up on bad sleep reads moderate', async () => {
    const userId = await freshUser(pool, 'cal-build@example.com');
    for (const daysAgo of [8, 15, 22]) {
      await logSession(pool, userId, daysAgo, 1000);
    }
    await logSession(pool, userId, 1, 1500);
    const load = await readTrainingLoad(pool, userId);
    const level = riskLevelFor(k, load, [{
      sleepQuality: 'poor',
      muscleSoreness: 'moderate',
      energy: 'low',
      stress: 'moderate',
    }]);
    assert.equal(level, 'moderate', `load ${load} plus a rough morning`);
  });

  await t.test('the clamp keeps volume alone below high', async () => {
    const userId = await freshUser(pool, 'cal-spike@example.com');
    await logSession(pool, userId, 22, 100);
    await logSession(pool, userId, 1, 100000);
    const load = await readTrainingLoad(pool, userId);
    const level = riskLevelFor(k, load, [{
      sleepQuality: 'excellent',
      muscleSoreness: 'none',
      energy: 'high',
      stress: 'very_low',
    }]);
    // Rested, with the largest spike the index can express. The design says
    // one signal alone never reaches `high`; this is what makes that true.
    assert.equal(level, 'moderate', `load ${load} on a perfect morning`);
    assert.ok(
      MAX_LOAD / k.loadDivisor < k.highAt,
      `the clamp must stay under risk.py's high threshold`,
    );
  });
});
