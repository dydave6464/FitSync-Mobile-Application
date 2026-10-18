'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');

const ANSWERS = {
  sleepQuality: 'poor',
  muscleSoreness: 'severe',
  energy: 'low',
  stress: 'high',
};

/// Records what the route sent, and answers like the real estimator would.
function recordingMl() {
  const calls = [];
  return {
    calls,
    async estimateInjuryRisk(payload) {
      calls.push(payload);
      return { riskLevel: 'moderate', trainingLoadScore: 42.5 };
    },
  };
}

test('recovery routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const ml = recordingMl();
  const app = buildTestApp({ pool, ml });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email: 'rec@example.com', password: 's3cret-pass', fullName: 'R' })
    .expect(201);
  await markEmailVerified(pool, reg.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'rec@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/recovery').expect(401);
    await request(app).post('/api/v1/recovery/checkin').send(ANSWERS).expect(401);
  });

  await t.test('an empty tab answers nulls, not an error', async () => {
    const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
    assert.equal(res.body.data.todayCheckin, null);
    assert.equal(res.body.data.latestEstimate, null);
    assert.equal(res.body.data.checkinCount, 0);
    assert.equal(res.body.data.load.length, 7);
    // Six groups, none trained yet, in body order.
    assert.deepEqual(res.body.data.muscles.map((m) => [m.group, m.lastTrained, m.daysAgo]), [
      ['chest', null, null], ['back', null, null], ['shoulders', null, null],
      ['arms', null, null], ['legs', null, null], ['core', null, null],
    ]);
  });

  await t.test('a bad answer is a 400 naming the field', async () => {
    const res = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send({ ...ANSWERS, energy: 'fantastic' }).expect(400);
    assert.equal(res.body.error.code, 'INVALID_CHECKIN');
    assert.match(res.body.error.message, /energy/);
  });

  await t.test('a missing answer is a 400 naming the field', async () => {
    const body = { ...ANSWERS };
    delete body.stress;
    const res = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(body).expect(400);
    assert.equal(res.body.error.code, 'INVALID_CHECKIN');
    assert.match(res.body.error.message, /stress/);
  });

  await t.test('a check-in stores an estimate against itself', async () => {
    const post = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);

    assert.equal(post.body.data.estimate.riskLevel, 'moderate');
    assert.equal(post.body.data.checkin.sleepQuality, 'poor');

    const [[row]] = await pool.query(
      `SELECT e.risk_level, e.checkin_id, c.checkin_date
         FROM injury_risk_estimates e
         JOIN morning_checkins c ON c.checkin_id = e.checkin_id`,
    );
    assert.equal(row.risk_level, 'moderate');
    assert.equal(row.checkin_id, post.body.data.checkin.checkinId);
  });

  await t.test('the ML service is sent the spellings risk.py looks up',
    async () => {
      const payload = ml.calls.at(-1);
      // Asserted on the values, not just that a call happened: risk.py reads
      // these with .get(value, 0.0), so a wrong spelling scores zero penalty
      // and raises nothing.
      assert.equal(payload.checkins[0].sleepQuality, 'poor');
      assert.equal(payload.checkins[0].muscleSoreness, 'severe');
      assert.equal(typeof payload.load, 'number');
      assert.ok(Number.isFinite(payload.load));
    });

  await t.test('the tab then serves the stored estimate and its date',
    async () => {
      const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
      assert.equal(res.body.data.latestEstimate.riskLevel, 'moderate');
      assert.equal(res.body.data.latestEstimate.trainingLoadScore, 42.5);
      assert.match(res.body.data.latestEstimate.checkinDate, /^\d{4}-\d{2}-\d{2}$/);
      assert.equal(res.body.data.todayCheckin.energy, 'low');
    });

  await t.test('a second check-in the same day updates it', async () => {
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send({ ...ANSWERS, energy: 'high' }).expect(201);

    const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM morning_checkins');
    assert.equal(n, 1, 'one row per day');

    const [[{ e }]] = await pool.query('SELECT COUNT(*) AS e FROM injury_risk_estimates');
    assert.equal(e, 2, 'estimates are append-only');
  });
});

test('recovery survives the ML service being down', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({
    pool,
    ml: {
      async estimateInjuryRisk() { throw new Error('ECONNREFUSED'); },
    },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email: 'down@example.com', password: 's3cret-pass', fullName: 'D' })
    .expect(201);
  await markEmailVerified(pool, reg.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'down@example.com', password: 's3cret-pass' }).expect(200);

  // The check-in is the user's own data, so it is kept. But no estimate is
  // invented for it: a stored 'low' would show on Home as "manageable" and
  // be indistinguishable from a real one.
  const auth = { Authorization: `Bearer ${login.body.data.token}` };
  const post = await request(app).post('/api/v1/recovery/checkin')
    .set(auth).send(ANSWERS).expect(201);

  assert.equal(post.body.data.estimate, null);
  assert.equal(post.body.data.checkin.sleepQuality, ANSWERS.sleepQuality);

  const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM morning_checkins');
  assert.equal(n, 1, 'the check-in is kept');
  const [[{ e }]] = await pool.query('SELECT COUNT(*) AS e FROM injury_risk_estimates');
  assert.equal(e, 0, 'no estimate is stored for it');

  const overview = await request(app).get('/api/v1/recovery').set(auth).expect(200);
  assert.equal(overview.body.data.latestEstimate ?? null, null);
});

/// How much this morning's answers are actually worth.
///
/// risk.py averages the recovery penalty across every check-in it is handed,
/// so the width of the window is the weight today carries. This asserts the
/// window by its effect -- an older check-in that must not be averaged in --
/// rather than by reading the constant back.
test('the estimator only sees the last few days of check-ins', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const ml = recordingMl();
  const app = buildTestApp({ pool, ml });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email: 'window@example.com', password: 's3cret-pass', fullName: 'W' })
    .expect(201);
  const { userId } = reg.body.data.user;
  await markEmailVerified(pool, userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'window@example.com', password: 's3cret-pass' }).expect(200);

  // A fine morning last week. Inside a 14-day window it halves the penalty
  // this morning's answers produce; it is too old to say anything about how
  // this user should train today.
  await pool.query(
    `INSERT INTO morning_checkins
       (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
     VALUES (?, DATE_SUB(CURDATE(), INTERVAL 5 DAY),
             'excellent', 'none', 'high', 'very_low')`,
    [userId],
  );

  await request(app).post('/api/v1/recovery/checkin')
    .set('Authorization', `Bearer ${login.body.data.token}`)
    .send(ANSWERS).expect(201);

  const { checkins } = ml.calls.at(-1);
  assert.equal(checkins.length, 1, 'last week must not dilute this morning');
  assert.equal(checkins[0].sleepQuality, 'poor');
});

test('the tab says how many check-ins the estimate rests on', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool, ml: recordingMl() });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { userId, auth } = await signIn(app, pool, 'count@example.com');
  // Yesterday's is inside the estimator's window; five days ago is not.
  for (const daysAgo of [1, 5]) {
    await pool.query(
      `INSERT INTO morning_checkins
         (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
       VALUES (?, DATE_SUB(CURDATE(), INTERVAL ? DAY), 'good', 'mild', 'moderate', 'low')`,
      [userId, daysAgo],
    );
  }
  await request(app).post('/api/v1/recovery/checkin').set(auth).send(ANSWERS).expect(201);

  const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
  // The same days the estimator was sent: today and yesterday.
  assert.equal(res.body.data.checkinCount, 2);
});

/// Registers and logs in a user against [app]; answers their id and headers.
async function signIn(app, pool, email) {
  const reg = await request(app).post('/api/v1/auth/register')
    .send({ email, password: 's3cret-pass', fullName: 'U' })
    .expect(201);
  const { userId } = reg.body.data.user;
  await markEmailVerified(pool, userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email, password: 's3cret-pass' }).expect(200);
  return { userId, auth: { Authorization: `Bearer ${login.body.data.token}` } };
}

async function region(pool, name, group) {
  const [res] = await pool.query(
    'INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, ?)',
    [name, group],
  );
  return res.insertId;
}

async function painReport(pool, userId, daysAgo, painLevel, injuryId) {
  const [s] = await pool.query(
    `INSERT INTO workout_sessions (user_id, status, session_date)
     VALUES (?, 'completed', DATE_SUB(CURDATE(), INTERVAL ? DAY))`,
    [userId, daysAgo],
  );
  await pool.query(
    `INSERT INTO session_outcomes (user_id, session_id, pain_level, injury_id)
     VALUES (?, ?, ?, ?)`,
    [userId, s.insertId, painLevel, painLevel === 'none' ? null : injuryId],
  );
}

test('the estimator is sent the user\'s injuries and worst recent pain', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const ml = recordingMl();
  const app = buildTestApp({ pool, ml });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const knee = await region(pool, 'Knee (route test)', 'lower_body');
  const shoulder = await region(pool, 'Shoulder (route test)', 'upper_body');
  const me = await signIn(app, pool, 'hist@example.com');
  const other = await signIn(app, pool, 'hist-other@example.com');

  await t.test('no injuries and no reports send an empty history and no recentPain', async () => {
    await request(app).post('/api/v1/recovery/checkin')
      .set(me.auth).send(ANSWERS).expect(201);
    const payload = ml.calls.at(-1);
    assert.deepEqual(payload.injuryHistory, []);
    assert.equal(payload.recentPain ?? null, null);
  });

  await t.test('the profile injuries go as plan refs, and the worst pain inside 14 days', async () => {
    await pool.query(
      "INSERT INTO user_injuries (user_id, injury_id, side) VALUES (?, ?, 'left')",
      [me.userId, knee],
    );
    // Someone else's injury and their severe pain must never ride along.
    await pool.query(
      'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)', [other.userId, shoulder],
    );
    await painReport(pool, other.userId, 1, 'severe', shoulder);
    // Inside: day 13. Outside: day 14, which would otherwise win.
    await painReport(pool, me.userId, 13, 'mild', knee);
    await painReport(pool, me.userId, 14, 'severe', knee);

    await request(app).post('/api/v1/recovery/checkin')
      .set(me.auth).send(ANSWERS).expect(201);
    const payload = ml.calls.at(-1);
    assert.deepEqual(payload.injuryHistory, [{ injuryId: knee, regionGroup: 'lower_body' }]);
    assert.equal(payload.recentPain, 'mild');
  });
});

test('what drove the estimate is stored and served back', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'drove@example.com');

  await t.test('source, load and drivers come back on the tab', async () => {
    answer = {
      riskLevel: 'moderate',
      trainingLoadScore: 47.25,
      source: 'model',
      modelVersion: 'risk-rf-sim-1',
      loadPct: 35,
      drivers: [
        { key: 'sleep', value: 'poor' },
        { key: 'load', value: 35 },
        { key: 'injury_history', value: 2 },
      ],
    };
    const post = await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    assert.equal(post.body.data.estimate.source, 'model');
    assert.deepEqual(post.body.data.estimate.drivers, answer.drivers);

    const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
    const est = res.body.data.latestEstimate;
    assert.equal(est.riskLevel, 'moderate');
    assert.equal(est.trainingLoadScore, 47.25);
    assert.equal(est.source, 'model');
    assert.equal(est.loadPct, 35);
    assert.deepEqual(est.drivers, answer.drivers);

    const [[row]] = await pool.query(
      'SELECT model_version FROM injury_risk_estimates ORDER BY estimate_id DESC LIMIT 1',
    );
    assert.equal(row.model_version, 'risk-rf-sim-1');
  });

  await t.test('unknown keys and mistyped values are dropped, and at most three are kept', async () => {
    answer = {
      riskLevel: 'high',
      trainingLoadScore: 72,
      source: 'rules',
      modelVersion: null,
      loadPct: 120,
      drivers: [
        { key: 'horoscope', value: 'bad' },
        { key: 'load', value: 'lots' },
        { key: 'sleep', value: 'dreadful' },
        { key: 'injury_history', value: 1.5 },
        'not an object',
        null,
        { key: 'recent_pain', value: 'severe' },
        { key: 'load', value: 120 },
        { key: 'soreness', value: 'severe' },
        { key: 'stress', value: 'high' },
      ],
    };
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    const res = await request(app).get('/api/v1/recovery').set(auth).expect(200);
    assert.deepEqual(res.body.data.latestEstimate.drivers, [
      { key: 'recent_pain', value: 'severe' },
      { key: 'load', value: 120 },
      { key: 'soreness', value: 'severe' },
    ]);
    assert.equal(res.body.data.latestEstimate.source, 'rules');
  });

  await t.test('an unknown source or an out-of-range load is stored as null, not refused', async () => {
    answer = {
      riskLevel: 'low', trainingLoadScore: 12, source: 'oracle', loadPct: 5000, drivers: [],
    };
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    const est = (await request(app).get('/api/v1/recovery').set(auth).expect(200))
      .body.data.latestEstimate;
    assert.equal(est.riskLevel, 'low');
    assert.equal(est.source, null);
    assert.equal(est.loadPct, null);
    assert.deepEqual(est.drivers, []);
  });

  await t.test('an answer from a service that predates drivers stores them as null', async () => {
    answer = { riskLevel: 'low', trainingLoadScore: 8 };
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    const [[row]] = await pool.query(
      `SELECT source, model_version, load_pct, drivers
         FROM injury_risk_estimates ORDER BY estimate_id DESC LIMIT 1`,
    );
    assert.deepEqual(
      [row.source, row.model_version, row.load_pct, row.drivers],
      [null, null, null, null],
    );
  });
});

test('a malformed ML answer keeps the check-in and stores no estimate', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'malformed@example.com');

  const cases = [
    ['a bare string', 'high'],
    ['an array', []],
    ['an unknown level', { riskLevel: 'extreme', trainingLoadScore: 50 }],
    ['no level', { trainingLoadScore: 50 }],
    ['a score that is not a number', { riskLevel: 'low', trainingLoadScore: 'abc' }],
    ['a score above 100', { riskLevel: 'high', trainingLoadScore: 250 }],
    ['a negative score', { riskLevel: 'low', trainingLoadScore: -1 }],
  ];
  for (const [name, value] of cases) {
    await t.test(name, async () => {
      answer = value;
      const post = await request(app).post('/api/v1/recovery/checkin')
        .set(auth).send(ANSWERS).expect(201);
      assert.equal(post.body.data.estimate, null);
      assert.equal(post.body.data.checkin.sleepQuality, ANSWERS.sleepQuality);
      const [[{ e }]] = await pool.query('SELECT COUNT(*) AS e FROM injury_risk_estimates');
      assert.equal(e, 0);
    });
  }

  const [[{ n }]] = await pool.query('SELECT COUNT(*) AS n FROM morning_checkins');
  assert.equal(n, 1, 'the check-in is kept');
});

test('only inputs that could reach the 5-point driver bar are kept', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'bar@example.com');

  async function storedDrivers(drivers) {
    answer = { riskLevel: 'moderate', trainingLoadScore: 45, source: 'rules', drivers };
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    return (await request(app).get('/api/v1/recovery').set(auth).expect(200))
      .body.data.latestEstimate.drivers;
  }

  await t.test('everyday answers and small loads are dropped', async () => {
    const drivers = await storedDrivers([
      { key: 'load', value: 9.99 },
      { key: 'load', value: 0 },
      { key: 'load', value: -20 },
      { key: 'sleep', value: 'good' },
      { key: 'sleep', value: 'excellent' },
      { key: 'soreness', value: 'none' },
      { key: 'soreness', value: 'mild' },
      { key: 'energy', value: 'moderate' },
      { key: 'energy', value: 'high' },
      { key: 'stress', value: 'low' },
      { key: 'stress', value: 'very_low' },
      { key: 'injury_history', value: 0 },
      { key: 'recent_pain', value: 'none' },
    ]);
    assert.deepEqual(drivers, []);
  });

  await t.test('each input at the bar is kept, in the service\'s order', async () => {
    const atBar = [
      [{ key: 'load', value: 10 }, { key: 'injury_history', value: 1 }, { key: 'recent_pain', value: 'mild' }],
      [{ key: 'sleep', value: 'fair' }, { key: 'soreness', value: 'moderate' }, { key: 'energy', value: 'low' }],
      [{ key: 'stress', value: 'moderate' }, { key: 'sleep', value: 'poor' }, { key: 'energy', value: 'very_low' }],
    ];
    for (const drivers of atBar) {
      assert.deepEqual(await storedDrivers(drivers), drivers);
    }
  });

  await t.test('a dropped everyday answer does not use up one of the three places', async () => {
    const drivers = await storedDrivers([
      { key: 'sleep', value: 'good' },
      { key: 'stress', value: 'high' },
      { key: 'load', value: 3 },
      { key: 'soreness', value: 'severe' },
      { key: 'recent_pain', value: 'moderate' },
    ]);
    assert.deepEqual(drivers, [
      { key: 'stress', value: 'high' },
      { key: 'soreness', value: 'severe' },
      { key: 'recent_pain', value: 'moderate' },
    ]);
  });
});

test('the check-in answer and the tab agree on drivers for the same row', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'agree@example.com');

  const cases = [
    ['a source with no drivers field', { riskLevel: 'low', trainingLoadScore: 10, source: 'rules' }, 'rules'],
    ['a source with drivers that are not a list', { riskLevel: 'low', trainingLoadScore: 10, source: 'model', drivers: 'sleep' }, 'model'],
    ['a source with an empty list', { riskLevel: 'low', trainingLoadScore: 10, source: 'rules', drivers: [] }, 'rules'],
    ['no source and no drivers (an old service)', { riskLevel: 'low', trainingLoadScore: 10 }, null],
  ];
  for (const [name, value, source] of cases) {
    await t.test(name, async () => {
      answer = value;
      const post = (await request(app).post('/api/v1/recovery/checkin')
        .set(auth).send(ANSWERS).expect(201)).body.data.estimate;
      const got = (await request(app).get('/api/v1/recovery').set(auth).expect(200))
        .body.data.latestEstimate;
      assert.equal(post.source, source);
      assert.equal(got.source, source);
      assert.deepEqual(post.drivers, []);
      assert.deepEqual(got.drivers, []);
    });
  }
});

test('a refused ML answer is logged by its key fields, without personal data', async (t) => {
  const { Writable } = require('node:stream');
  const { createLogger } = require('../src/lib/logger');
  let output = '';
  const destination = new Writable({
    write(chunk, _encoding, callback) { output += chunk.toString(); callback(); },
  });
  // production env avoids the pino-pretty worker thread, which would bypass
  // this synchronous capture stream.
  const logger = createLogger({ level: 'warn', env: 'production', destination });
  const lines = () => output.split('\n').filter(Boolean).map((l) => JSON.parse(l));

  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    logger,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'refused-log@example.com');

  await t.test('an object answer logs its level, score, source, load and driver keys', async () => {
    output = '';
    answer = {
      riskLevel: 'extreme',
      trainingLoadScore: 250,
      source: 'model',
      loadPct: 35,
      drivers: [{ key: 'sleep', value: 'poor' }, { key: 'recent_pain', value: 'severe' }],
    };
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    const line = lines().find((l) => /malformed/.test(l.msg));
    assert.ok(line, 'expected a warning for the refused answer');
    assert.deepEqual(line.mlAnswer, {
      riskLevel: 'extreme',
      trainingLoadScore: 250,
      source: 'model',
      loadPct: 35,
      driverKeys: ['sleep', 'recent_pain'],
    });
    const raw = JSON.stringify(line);
    assert.ok(!raw.includes('refused-log@example.com'), 'no email in the log');
    assert.ok(!raw.includes('"poor"'), 'no driver values (health answers) in the log');
    assert.ok(!raw.includes('"severe"'), 'no driver values (health answers) in the log');
  });

  await t.test('a non-object answer logs only its type', async () => {
    output = '';
    answer = 'high';
    await request(app).post('/api/v1/recovery/checkin')
      .set(auth).send(ANSWERS).expect(201);
    const line = lines().find((l) => /malformed/.test(l.msg));
    assert.ok(line);
    assert.deepEqual(line.mlAnswer, { type: 'string' });
  });
});

test('a load the DECIMAL(5,2) column would round to 1000.00 is never stored', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  let answer;
  const app = buildTestApp({
    pool,
    ml: { async estimateInjuryRisk() { return answer; } },
  });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });
  const { auth } = await signIn(app, pool, 'boundary@example.com');

  const cases = [
    [999.99, 999.99],
    [999.994, 999.99],
    [999.995, null],
    [999.999, null],
    [1000, null],
  ];
  for (const [sent, stored] of cases) {
    await t.test(`${sent} is stored as ${stored}`, async () => {
      answer = { riskLevel: 'high', trainingLoadScore: 90, source: 'rules', loadPct: sent, drivers: [] };
      const post = await request(app).post('/api/v1/recovery/checkin')
        .set(auth).send(ANSWERS).expect(201);
      assert.equal(post.body.data.estimate.loadPct, stored);
      const est = (await request(app).get('/api/v1/recovery').set(auth).expect(200))
        .body.data.latestEstimate;
      assert.equal(est.riskLevel, 'high');
      assert.equal(est.loadPct, stored);
    });
  }
});
