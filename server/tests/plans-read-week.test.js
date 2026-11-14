'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { seedInjuries } = require('../src/db/seed-injuries');

test('POST /plans/read-week', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  // The injury catalogue the reader maps names onto. No migration fills it;
  // seed-injuries.js does, as in production.
  await seedInjuries(testDbConfig());
  const [[knee]] = await pool.query("SELECT injury_id FROM injuries WHERE name = 'Knee'");

  const calls = [];
  let answer = (text) => ({ splitStyle: 'push_pull_legs', minutes: 50, weekdays: [1, 3, 5],
    daysPerWeek: null, injuries: [{ name: 'Knee', side: 'left' }], mentionsGoal: false, text });
  const weekReader = { read: async (args) => { calls.push(args); return answer(args.text); } };
  const build = () => buildTestApp({ pool, weekReader });
  let app = build();
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'r@example.com', password: 's3cret-pass', fullName: 'R' }).expect(201);
  await markEmailVerified(pool, res.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'r@example.com', password: 's3cret-pass' }).expect(200);
  const auth = `Bearer ${login.body.data.token}`;
  const read = (text) => request(app).post('/api/v1/plans/read-week').set('Authorization', auth).send({ text });

  await t.test('a reading comes back validated', async () => {
    const r = await read('PPL Mon Wed Fri, 50 min, left knee').expect(200);
    assert.deepEqual(r.body.data, {
      splitStyle: 'push_pull_legs', sessionLengthMin: 45, requestedMinutes: 50,
      weekdays: [1, 3, 5], daysPerWeek: null, injuries: [{ injuryId: knee.injury_id, side: 'left' }],
      mentionsGoal: false, source: 'ai',
    });
    assert.ok(calls.at(-1).injuryNames.includes('Knee'));
  });

  await t.test('the same sentence is answered from the cache', async () => {
    const before = calls.length;
    await read('  ppl MON wed fri, 50 MIN,   left knee ').expect(200);
    assert.equal(calls.length, before);
  });

  await t.test('text must be 1 to 300 characters', async () => {
    assert.equal((await read('   ').expect(400)).body.error.code, 'INVALID_WEEK_TEXT');
    await read('x'.repeat(301)).expect(400);
    await request(app).post('/api/v1/plans/read-week').set('Authorization', auth).send({ text: 7 }).expect(400);
  });

  await t.test('a failed reading is AI_BUSY and is not cached', async () => {
    answer = () => null;
    const r = await read('stub busy one').expect(503);
    assert.equal(r.body.error.code, 'AI_BUSY');
    answer = (text) => ({ splitStyle: 'full_body', text });
    await read('stub busy one').expect(200);
  });

  await t.test('the 31st reading of the day is READ_LIMIT; cache hits and failures do not count', async () => {
    app = build(); // a fresh limiter and cache
    answer = () => null;
    await read('failure does not count').expect(503);
    answer = (text) => ({ splitStyle: 'full_body', text });
    for (let i = 1; i <= 30; i += 1) await read(`sentence number ${i}`).expect(200);
    await read('sentence number 1').expect(200); // cached
    const r = await read('sentence number 31').expect(429);
    assert.equal(r.body.error.code, 'READ_LIMIT');
    assert.equal(r.body.error.message, 'AI reading is used up for today.');
  });

  await t.test('a reading never changes the profile', async () => {
    app = build();
    const before = (await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200)).body;
    answer = () => ({ weekdays: [2, 4], injuries: [{ name: 'Knee', side: 'right' }] });
    await read('tue thu, right knee').expect(200);
    const after = (await request(app).get('/api/v1/profile').set('Authorization', auth).expect(200)).body;
    assert.deepEqual(after, before);
  });

  await t.test('needs a signed-in user', async () => {
    await request(app).post('/api/v1/plans/read-week').send({ text: 'ppl' }).expect(401);
  });
});
