'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { markEmailVerified } = require('../src/db/users');
const { manilaDay } = require('../src/lib/manila-day');

test('body weight routes', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const res = await request(app).post('/api/v1/auth/register')
    .send({ email: 'bw@example.com', password: 's3cret-pass', fullName: 'W' })
    .expect(201);
  await markEmailVerified(pool, res.body.data.user.userId);
  const login = await request(app).post('/api/v1/auth/login')
    .send({ email: 'bw@example.com', password: 's3cret-pass' }).expect(200);
  const auth = { Authorization: `Bearer ${login.body.data.token}` };

  await t.test('requires a token', async () => {
    await request(app).get('/api/v1/profile/body-weight').expect(401);
  });

  await t.test('an unknown period is a 400', async () => {
    await request(app).get('/api/v1/profile/body-weight?period=decade')
      .set(auth).expect(400);
  });


  // 'decade' above names no property at all. 'constructor' names one every
  // object inherits, so a bare SUMMARY_WINDOWS[period] hands back a truthy
  // function, the null the route turns into the 400 never happens, and the
  // function reaches the query as a bind parameter -- a 500.
  await t.test('a prototype property is a 400, not a 500', async () => {
    for (const period of ['constructor', 'toString', '__proto__']) {
      await request(app).get(`/api/v1/profile/body-weight?period=${period}`)
        .set(auth).expect(400);
    }
  });

  // `start` and `entries` let the card say "since you started" even when a
  // goal weight, not the start, is the dashed reference line.
  await t.test('before any weigh-in there is no start and no entries', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.equal(get.body.data.start, null);
    assert.equal(get.body.data.entries, 0);
  });

  await t.test('posting an entry returns it', async () => {
    const post = await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 71.4 }).expect(201);
    assert.equal(post.body.data.weightKg, 71.4);
    assert.match(post.body.data.loggedOn, /^\d{4}-\d{2}-\d{2}$/);
  });

  await t.test('and it appears in the series with the unit', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.equal(get.body.data.points.length, 1);
    assert.equal(get.body.data.points[0].weightKg, 71.4);
    assert.equal(get.body.data.unit, 'kg');
  });

  await t.test('the reference falls back to the starting weight', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.deepEqual(get.body.data.reference, { kind: 'start', weightKg: 71.4 });
  });

  await t.test('the first weigh-in is the start, and it is counted', async () => {
    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.equal(get.body.data.entries, 1);
    assert.equal(get.body.data.start.weightKg, 71.4);
    assert.equal(get.body.data.start.loggedOn, get.body.data.points[0].loggedOn);
  });

  await t.test('a nonsense weight is a 400, not a stored row', async () => {
    const res = await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 714 }).expect(400);
    assert.equal(res.body.error.code, 'WEIGHT_OUT_OF_RANGE');
    assert.equal(res.body.error.message, 'Enter a weight between 20 and 500 kg.');
    assert.deepEqual(res.body.error.details, [{ field: 'weightKg', min: 20, max: 500, unit: 'kg' }]);
    const [rows] = await pool.query('SELECT COUNT(*) AS n FROM body_weight_logs');
    assert.equal(Number(rows[0].n), 1, 'still just the good one');
  });

  await t.test('a missing weight is a 400', async () => {
    await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({}).expect(400);
  });

  // Last: it adds back-dated weigh-ins and a goal, which the tests above
  // must not see.
  await t.test('the start is the earliest weigh-in, even outside the period and with a goal set', async () => {
    await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 74.2, loggedOn: '2026-01-05' }).expect(201);
    await request(app).post('/api/v1/profile/body-weight')
      .set(auth).send({ weightKg: 73.0, loggedOn: '2026-02-05' }).expect(201);
    await request(app).patch('/api/v1/profile').set(auth).send({ goalWeightKg: 68 }).expect(200);

    const get = await request(app).get('/api/v1/profile/body-weight?period=week')
      .set(auth).expect(200);
    assert.deepEqual(get.body.data.start, { loggedOn: '2026-01-05', weightKg: 74.2 });
    assert.equal(get.body.data.entries, 3);
    assert.deepEqual(get.body.data.reference, { kind: 'goal', weightKg: 68 });
  });

  // ----- Deleting a mistaken weigh-in (PS-20), and loggedOn checks on POST.
  let seq = 0;
  const freshUser = async () => {
    seq += 1;
    const email = `bw-del${seq}@example.com`;
    const reg = await request(app).post('/api/v1/auth/register')
      .send({ email, password: 's3cret-pass', fullName: 'D' }).expect(201);
    const userId = reg.body.data.user.userId;
    await markEmailVerified(pool, userId);
    const signIn = await request(app).post('/api/v1/auth/login')
      .send({ email, password: 's3cret-pass' }).expect(200);
    const h = { Authorization: `Bearer ${signIn.body.data.token}` };
    return {
      userId,
      log: (loggedOn, weightKg) => request(app).post('/api/v1/profile/body-weight')
        .set(h).send({ weightKg, loggedOn }),
      del: (loggedOn) => request(app).delete(`/api/v1/profile/body-weight/${loggedOn}`).set(h),
      profileWeight: async () => {
        const res = await request(app).get('/api/v1/profile').set(h).expect(200);
        const w = res.body.data.profile.weightKg;
        return w === null ? null : Number(w);
      },
      rows: async () => (await pool.query(
        'SELECT log_date FROM body_weight_logs WHERE user_id = ?', [userId],
      ))[0].length,
    };
  };
  const A = '2026-03-01';
  const B = '2026-03-02';
  const C = '2026-03-03';

  await t.test('deleting a weigh-in requires a token', async () => {
    const res = await request(app).delete(`/api/v1/profile/body-weight/${A}`).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('deleting on a day that is not real is a 400', async () => {
    const u = await freshUser();
    await u.log(A, 80).expect(201);
    for (const day of ['2026-02-31', '2026-13-01', 'abc']) {
      const res = await u.del(day).expect(400);
      assert.equal(res.body.error.code, 'DATE_INVALID', day);
      assert.equal(res.body.error.message, "That isn't a real day.", day);
    }
  });

  await t.test('deleting a day with no weigh-in is a 404', async () => {
    const u = await freshUser();
    await u.log(A, 80).expect(201);
    await u.log(B, 79).expect(201);
    const res = await u.del('2026-03-09').expect(404);
    assert.equal(res.body.error.code, 'WEIGH_IN_NOT_FOUND');
    assert.equal(res.body.error.message, "There's no weigh-in on that day.");
    assert.equal(await u.rows(), 2);
  });

  await t.test('deleting a middle day, then the newest, then refusing the last', async () => {
    const u = await freshUser();
    await u.log(A, 80).expect(201);
    await u.log(B, 79).expect(201);
    await u.log(C, 78).expect(201);
    assert.equal(await u.profileWeight(), 78);

    const middle = await u.del(B).expect(200);
    assert.deepEqual(middle.body.data, {
      deleted: { loggedOn: B, weightKg: 79 },
      start: { loggedOn: A, weightKg: 80 },
      entries: 2,
      weightKg: 78,
    });
    assert.equal(await u.profileWeight(), 78, 'an older day leaves the profile weight alone');

    const newest = await u.del(C).expect(200);
    assert.deepEqual(newest.body.data, {
      deleted: { loggedOn: C, weightKg: 78 },
      start: { loggedOn: A, weightKg: 80 },
      entries: 1,
      weightKg: 80,
    });
    assert.equal(await u.profileWeight(), 80, 'the profile follows the newest weigh-in left');

    const last = await u.del(A).expect(409);
    assert.equal(last.body.error.code, 'ONLY_WEIGH_IN');
    assert.equal(last.body.error.message,
      "You can't delete your only weigh-in. To fix it, log the right weight for that day. It replaces this one.");
    assert.equal(await u.rows(), 1, 'the only weigh-in stays');
    assert.equal(await u.profileWeight(), 80);
  });

  await t.test('deleting the earliest day moves the start to the next one', async () => {
    const u = await freshUser();
    await u.log(A, 80).expect(201);
    await u.log(B, 79).expect(201);
    await u.log(C, 78).expect(201);
    const res = await u.del(A).expect(200);
    assert.deepEqual(res.body.data.start, { loggedOn: B, weightKg: 79 });
    assert.equal(res.body.data.entries, 2);
    assert.equal(res.body.data.weightKg, 78);
    assert.equal(await u.profileWeight(), 78);
  });

  await t.test("one user's delete never touches another user's weigh-in", async () => {
    const first = await freshUser();
    const second = await freshUser();
    await first.log(A, 80).expect(201);
    await first.log(B, 79).expect(201);
    await second.log(B, 60).expect(201);
    await second.log(C, 61).expect(201);

    await first.del(B).expect(200);
    assert.equal(await second.rows(), 2, "the second user's day B survives");
    assert.equal(await second.profileWeight(), 61);

    const res = await second.del(A).expect(404);
    assert.equal(res.body.error.code, 'WEIGH_IN_NOT_FOUND');
    assert.equal(await first.rows(), 1, "the first user's day A survives");
  });

  // No unique key on (user_id, log_date), so a race could have left two.
  await t.test('every row for the day goes', async () => {
    const u = await freshUser();
    await u.log(A, 80).expect(201);
    await pool.query(
      'INSERT INTO body_weight_logs (user_id, weight_kg, log_date) VALUES (?, 77, ?), (?, 77, ?)',
      [u.userId, B, u.userId, B],
    );
    const res = await u.del(B).expect(200);
    assert.equal(res.body.data.entries, 1);
    assert.equal(await u.rows(), 1);
  });

  await t.test('a weigh-in on a day that is not real is a 400 and stores nothing', async () => {
    const u = await freshUser();
    for (const loggedOn of ['2026-02-31', '2026-13-01', 'abc', 20260301]) {
      const res = await u.log(loggedOn, 80).expect(400);
      assert.equal(res.body.error.code, 'DATE_INVALID', String(loggedOn));
      assert.equal(res.body.error.message, "That isn't a real day.");
    }
    assert.equal(await u.rows(), 0);
  });

  await t.test('a weigh-in for a future day is a 400 and leaves the profile weight', async () => {
    const u = await freshUser();
    await u.log(manilaDay(), 80).expect(201);
    const res = await u.log(manilaDay(-1), 70).expect(400);
    assert.equal(res.body.error.code, 'DATE_OUT_OF_RANGE');
    assert.equal(res.body.error.message, "A weigh-in can't be logged for a future day.");
    assert.equal(await u.profileWeight(), 80);
    assert.equal(await u.rows(), 1);
  });
});
