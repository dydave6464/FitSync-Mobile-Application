'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedExercises } = require('../src/db/seed-exercises');
const { markEmailVerified } = require('../src/db/users');
const FIXTURE = require('./fixtures/seeds/manifest-fixture.json');

test('undoing a generated plan', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  const [live] = await pool.query("SELECT name FROM exercises WHERE status='live' LIMIT 1");
  const known = live[0].name;

  let planNo = 0;
  // Every `overrides` the generator was handed, as handed, so a test can
  // see what reached ML rather than what the fake echoed back. One per
  // request: this fake returns the same exercises every time, so a request
  // after the first also makes a second ask (New plan with nothing changed),
  // with the same overrides -- plans-regenerate-variety.test.js pins that.
  const sentOverrides = [];
  const ml = {
    generatePlan: async (profile = {}) => {
      planNo += 1;
      if (!profile.avoid) sentOverrides.push(profile.overrides);
      const overrides = profile.overrides || {};
      return {
        name: `Plan ${planNo}`,
        splitStyle: overrides.splitStyle || 'full_body',
        daysPerWeek: 3,
        sessionLengthMin: overrides.sessionLengthMin || 45,
        weekNo: 1,
        exercises: [{ name: known, dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12' }],
      };
    },
    estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
  };
  const app = buildTestApp({ pool, ml });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const signUp = async (email) => {
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'U' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    return { userId: res.body.data.user.userId, auth: `Bearer ${login.body.data.token}` };
  };
  const reset = async () => {
    await pool.query('DELETE FROM workout_sessions');
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('UPDATE workout_plans SET replaced_plan_id = NULL');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
    planNo = 0;
    sentOverrides.length = 0;
  };
  const regenerate = (auth, body = {}) => request(app).post('/api/v1/plans/regenerate')
    .set('Authorization', auth).send({ splitStyle: 'full_body', daysPerWeek: 3, ...body }).expect(200);
  const active = async (auth) => (await request(app).get('/api/v1/plans/active')
    .set('Authorization', auth).expect(200)).body.data.plan;

  await t.test('a first plan has nothing to undo', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const res = await regenerate(auth);
    assert.equal(res.body.data.plan.previousPlan, null);
    const [[row]] = await pool.query('SELECT replaced_plan_id FROM workout_plans WHERE is_active = TRUE');
    assert.equal(row.replaced_plan_id, null);
  });

  await t.test('a second plan names the plan it replaced', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const first = (await regenerate(auth)).body.data.plan;
    const second = (await regenerate(auth)).body.data.plan;
    assert.deepEqual(second.previousPlan, { planId: first.planId, name: 'Plan 1' });
    assert.deepEqual((await active(auth)).previousPlan, { planId: first.planId, name: 'Plan 1' });
  });

  await t.test('Undo brings the replaced plan back and deletes nothing', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const first = (await regenerate(auth)).body.data.plan;
    const second = (await regenerate(auth)).body.data.plan;
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(200);
    assert.equal(res.body.data.plan.planId, first.planId);
    assert.equal(res.body.data.plan.previousPlan, null);
    const [rows] = await pool.query('SELECT plan_id, is_active FROM workout_plans ORDER BY plan_id');
    assert.deepEqual(rows.map((r) => [r.plan_id, Boolean(r.is_active)]),
      [[first.planId, true], [second.planId, false]]);
    const [[restored]] = await pool.query(
      'SELECT replaced_plan_id FROM workout_plans WHERE plan_id = ?', [first.planId]);
    assert.equal(restored.replaced_plan_id, null);
  });

  await t.test('there is no Undo of an Undo', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    await regenerate(auth);
    await regenerate(auth);
    await request(app).post('/api/v1/plans/restore-previous').set('Authorization', auth).expect(200);
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(409);
    assert.equal(res.body.error.code, 'NO_PREVIOUS_PLAN');
    assert.equal(res.body.error.message, "There's no earlier plan to bring back.");
  });

  await t.test('a plan restored by Undo, then replaced again, can be undone to', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const first = (await regenerate(auth)).body.data.plan;
    await regenerate(auth);
    await request(app).post('/api/v1/plans/restore-previous').set('Authorization', auth).expect(200);
    const third = (await regenerate(auth)).body.data.plan;
    assert.deepEqual(third.previousPlan, { planId: first.planId, name: 'Plan 1' });
  });

  await t.test('no plan at all is NO_PREVIOUS_PLAN', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(409);
    assert.equal(res.body.error.code, 'NO_PREVIOUS_PLAN');
  });

  await t.test('a workout on the new plan ends Undo', async () => {
    await reset();
    const { userId, auth } = await signUp('a@example.com');
    await regenerate(auth);
    const second = (await regenerate(auth)).body.data.plan;
    await pool.query(
      `INSERT INTO workout_sessions (user_id, plan_id, status, session_date)
       VALUES (?, ?, 'completed', CURDATE())`, [userId, second.planId]);
    assert.equal((await active(auth)).previousPlan, null);
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(409);
    assert.equal(res.body.error.code, 'PLAN_ALREADY_USED');
    assert.equal(res.body.error.message,
      "You've started a workout on the new plan, so the old one can't come back.");
  });

  await t.test('a workout in progress is refused first', async () => {
    await reset();
    const { userId, auth } = await signUp('a@example.com');
    await regenerate(auth);
    const second = (await regenerate(auth)).body.data.plan;
    await pool.query(
      `INSERT INTO workout_sessions (user_id, plan_id, status, session_date, started_at)
       VALUES (?, ?, 'in_progress', CURDATE(), NOW())`, [userId, second.planId]);
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(409);
    assert.equal(res.body.error.code, 'SESSION_IN_PROGRESS');
  });

  await t.test("another user's plans are never touched", async () => {
    await reset();
    const a = await signUp('a@example.com');
    const b = await signUp('b@example.com');
    // Interleaved, so B's plan is the newest active row in the table and
    // B's plans sit either side of A's.
    const a1 = (await regenerate(a.auth)).body.data.plan;
    await regenerate(b.auth);
    await regenerate(a.auth);
    const b2 = (await regenerate(b.auth)).body.data.plan;
    const bRows = async () => (await pool.query(
      `SELECT plan_id, is_active, replaced_plan_id FROM workout_plans
        WHERE user_id = ? ORDER BY plan_id`, [b.userId]))[0]
      .map((r) => [r.plan_id, Boolean(r.is_active), r.replaced_plan_id]);
    const before = await bRows();

    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', a.auth).expect(200);
    assert.equal(res.body.data.plan.planId, a1.planId);
    assert.deepEqual(await bRows(), before);

    // B's own Undo still has B's plan to bring back.
    const resB = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', b.auth).expect(200);
    assert.equal(resB.body.data.plan.planId, b2.previousPlan.planId);
    assert.equal((await active(a.auth)).planId, a1.planId);
  });

  await t.test('a chosen length reaches the generator as sent', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    const res = await regenerate(auth, { sessionLengthMin: 60 });
    assert.equal(res.body.data.plan.sessionLengthMin, 60);
  });

  await t.test('regenerate with 45, 60 and no length reaches ML as sent', async () => {
    await reset();
    const { auth } = await signUp('a@example.com');
    await regenerate(auth, { sessionLengthMin: 45 });
    await regenerate(auth, { sessionLengthMin: 60 });
    await regenerate(auth);
    assert.equal(sentOverrides.length, 3);
    assert.equal(sentOverrides[0].sessionLengthMin, 45);
    assert.equal(sentOverrides[1].sessionLengthMin, 60);
    // Auto sends no key, and none is made up on the way: ML decides.
    assert.ok(sentOverrides[2], 'the split and days still go as overrides');
    assert.equal(Object.hasOwn(sentOverrides[2], 'sessionLengthMin'), false);
  });

  await t.test('Undo needs a signed-in user', async () => {
    await request(app).post('/api/v1/plans/restore-previous').expect(401);
  });
});
