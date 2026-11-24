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

// New plan with nothing changed (2026-11-24). The generator is deterministic,
// so asking again with the same settings returns the plan the user already
// has. When the plan it returns has the same exercises as the current plan or
// the one before it, the route asks once more, naming both plans' exercises
// so the generator moves them to the back.
test('New plan with nothing changed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedExercises(testDbConfig(), JSON.parse(JSON.stringify(FIXTURE)));
  const [live] = await pool.query(
    "SELECT exercise_id, name FROM exercises WHERE status='live' ORDER BY exercise_id LIMIT 3",
  );
  assert.equal(live.length, 3, 'the fixture catalogue needs three live exercises');
  const [A, B, C] = live.map((r) => ({ exerciseId: r.exercise_id, name: r.name }));

  // A stand-in for the ML service with the same contract: the best plan is A,
  // and with avoid lists it takes the first exercise in neither, then the
  // first not in the current plan. `onlyA` is a catalogue with nothing else.
  let onlyA = false;
  const asks = [];
  const ml = {
    generatePlan: async (profile = {}) => {
      asks.push(profile);
      const overrides = profile.overrides || {};
      const avoid = profile.avoid;
      let pick = A;
      if (avoid && !onlyA) {
        const fresh = [A, B, C].find((x) => !avoid.current.includes(x.exerciseId)
          && !avoid.previous.includes(x.exerciseId));
        pick = fresh || [A, B, C].find((x) => !avoid.current.includes(x.exerciseId)) || A;
      }
      const exercises = [{ ...pick, dayNo: 1, orderNo: 1, targetSets: 3, targetReps: '8-12' }];
      if (overrides.splitStyle === 'upper_lower') {
        exercises.push({ ...B, dayNo: 2, orderNo: 1, targetSets: 3, targetReps: '8-12' });
      }
      return {
        name: 'Generated',
        splitStyle: overrides.splitStyle || 'full_body',
        daysPerWeek: 3,
        sessionLengthMin: 45,
        weekNo: 1,
        exercises,
      };
    },
    estimateInjuryRisk: async () => ({ riskLevel: 'low', trainingLoadScore: 0 }),
  };
  const app = buildTestApp({ pool, ml });

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let auth;
  t.beforeEach(async () => {
    await pool.query('DELETE FROM workout_sessions');
    await pool.query('DELETE FROM plan_exercises');
    await pool.query('UPDATE workout_plans SET replaced_plan_id = NULL');
    await pool.query('DELETE FROM workout_plans');
    await pool.query('DELETE FROM user_identities');
    await pool.query('DELETE FROM users');
    onlyA = false;
    const email = 'v@example.com';
    const res = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'V' }).expect(201);
    await markEmailVerified(pool, res.body.data.user.userId);
    const login = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    auth = `Bearer ${login.body.data.token}`;
    asks.length = 0;
  });

  const newPlan = async (body = {}) => {
    asks.length = 0;
    const res = await request(app).post('/api/v1/plans/regenerate')
      .set('Authorization', auth).send({ splitStyle: 'full_body', daysPerWeek: 3, ...body })
      .expect(200);
    return res.body.data.plan.exercises.map((e) => e.exerciseId);
  };

  await t.test('a first plan is asked for once, with nothing to avoid', async () => {
    assert.deepEqual(await newPlan(), [A.exerciseId]);
    assert.equal(asks.length, 1);
    assert.equal('avoid' in asks[0], false);
  });

  await t.test('the same plan again asks once more, avoiding the current exercises', async () => {
    await newPlan();
    assert.deepEqual(await newPlan(), [B.exerciseId]);
    assert.equal(asks.length, 2);
    assert.equal('avoid' in asks[0], false);
    assert.deepEqual(asks[1].avoid, { current: [A.exerciseId], previous: [] });
  });

  await t.test('the second ask keeps the settings and history of the first', async () => {
    await newPlan();
    await newPlan({ sessionLengthMin: 60 });
    const { avoid, ...secondAsk } = asks[1];
    assert.ok(avoid);
    assert.deepEqual(secondAsk, asks[0]);
  });

  await t.test('a third tap avoids the current plan most and the previous plan next', async () => {
    await newPlan();
    await newPlan();
    assert.deepEqual(await newPlan(), [C.exerciseId]);
    assert.equal(asks.length, 2);
    assert.deepEqual(asks[1].avoid, { current: [B.exerciseId], previous: [A.exerciseId] });
  });

  await t.test('a fourth tap comes back round to the first plan', async () => {
    await newPlan();
    await newPlan();
    await newPlan();
    assert.deepEqual(await newPlan(), [A.exerciseId]);
    assert.equal(asks.length, 1);
  });

  await t.test('a plan that already differs is saved without asking again', async () => {
    await newPlan();
    assert.deepEqual(await newPlan({ splitStyle: 'upper_lower' }), [A.exerciseId, B.exerciseId]);
    assert.equal(asks.length, 1);
  });

  await t.test('with nothing else to pick, the same plan is still saved', async () => {
    onlyA = true;
    await newPlan();
    assert.deepEqual(await newPlan(), [A.exerciseId]);
    assert.equal(asks.length, 2);
  });

  await t.test('Undo after a varied plan brings back the one it replaced', async () => {
    await newPlan();
    await newPlan();
    const res = await request(app).post('/api/v1/plans/restore-previous')
      .set('Authorization', auth).expect(200);
    assert.deepEqual(res.body.data.plan.exercises.map((e) => e.exerciseId), [A.exerciseId]);
  });
});
