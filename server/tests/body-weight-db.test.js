'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const bw = require('../src/db/body-weight');

async function makeUser(pool, email = 'w@example.com') {
  const [res] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name) VALUES (?, 'x', 'W')`,
    [email],
  );
  return res.insertId;
}

const daysAgo = (n) => `DATE_SUB(CURDATE(), INTERVAL ${n} DAY)`;

test('body weight db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('two writes on one day produce one row', async () => {
    const userId = await makeUser(pool, 'one-a-day@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });
    await bw.writeEntry(pool, userId, { weightKg: 70.9 });

    const [rows] = await pool.query(
      'SELECT weight_kg FROM body_weight_logs WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 1);
    assert.equal(Number(rows[0].weight_kg), 70.9, 'the later write wins');
  });

  await t.test('the newest entry syncs to users.weight_kg', async () => {
    const userId = await makeUser(pool, 'sync@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });

    const [[user]] = await pool.query(
      'SELECT weight_kg FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(Number(user.weight_kg), 71.4);
  });

  await t.test('a backdated entry does not clobber the current weight', async () => {
    const userId = await makeUser(pool, 'backdate@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 70.0 });

    const [[past]] = await pool.query(`SELECT ${daysAgo(30)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 99.0, loggedOn: past.d });

    const [[user]] = await pool.query(
      'SELECT weight_kg FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(Number(user.weight_kg), 70.0, 'today still wins');
  });

  await t.test('out-of-range input is rejected', async () => {
    const userId = await makeUser(pool, 'range@example.com');
    await assert.rejects(
      () => bw.writeEntry(pool, userId, { weightKg: 4 }),
      (err) => {
        assert.equal(err.code, 'WEIGHT_OUT_OF_RANGE');
        assert.equal(err.message, 'Enter a weight between 20 and 500 kg.');
        assert.deepEqual(err.details, [{ field: 'weightKg', min: 20, max: 500, unit: 'kg' }]);
        return true;
      },
    );
  });

  await t.test('a thin window widens rather than returning one point', async () => {
    const userId = await makeUser(pool, 'widen@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(40)} AS d`);
    const [[b]] = await pool.query(`SELECT ${daysAgo(35)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: b.d });

    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.widened, true);
    assert.equal(week.points.length, 2, 'both entries come back anyway');
    assert.ok(week.points[0].loggedOn < week.points[1].loggedOn, 'oldest first');
  });

  await t.test('an entry exactly at the window boundary is excluded, one day inside is not', async () => {
    const userId = await makeUser(pool, 'boundary@example.com');
    const [[edge]] = await pool.query(`SELECT ${daysAgo(7)} AS d`);
    const [[inside]] = await pool.query(`SELECT ${daysAgo(6)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 90, loggedOn: edge.d });
    await bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: inside.d });
    await bw.writeEntry(pool, userId, { weightKg: 78 });

    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.widened, false, 'two entries already sit inside the window');
    assert.equal(week.points.length, 2,
      'the entry from exactly 7 days ago must fall outside the week window');
    assert.ok(week.points.every((p) => p.weightKg !== 90),
      'the day-7 boundary entry must not appear in the week series');
  });

  await t.test('a full window does not widen', async () => {
    const userId = await makeUser(pool, 'nowiden@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(2)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 79 });

    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.widened, false);
    assert.equal(week.points.length, 2);
  });

  await t.test('one entry overall stays one point', async () => {
    const userId = await makeUser(pool, 'single@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80 });
    const week = await bw.readSeries(pool, userId, 'week');
    assert.equal(week.points.length, 1, 'widening cannot invent a second');
  });

  await t.test('the reference is the goal when there is one', async () => {
    const userId = await makeUser(pool, 'goal@example.com');
    await pool.query('UPDATE users SET goal_weight_kg = 68 WHERE user_id = ?', [userId]);
    await bw.writeEntry(pool, userId, { weightKg: 71.4 });

    assert.deepEqual(await bw.readReference(pool, userId), {
      kind: 'goal', weightKg: 68,
    });
  });

  await t.test('and the earliest entry when there is not', async () => {
    const userId = await makeUser(pool, 'start@example.com');
    const [[a]] = await pool.query(`SELECT ${daysAgo(10)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 75, loggedOn: a.d });
    await bw.writeEntry(pool, userId, { weightKg: 73 });

    assert.deepEqual(await bw.readReference(pool, userId), {
      kind: 'start', weightKg: 75,
    });
  });

  await t.test('an unknown period is null, not an empty series', async () => {
    const userId = await makeUser(pool, 'period@example.com');
    assert.equal(await bw.readSeries(pool, userId, 'decade'), null);
  });

  await t.test('an onboarding weight becomes the first chart point', async () => {
    const userId = await makeUser(pool, 'onboard@example.com');
    const { updateProfile } = require('../src/db/profile');
    await updateProfile(pool, userId, { weightKg: 78.5 });

    const series = await bw.readSeries(pool, userId, 'week');
    assert.equal(series.points.length, 1, 'the chart starts with a point');
    assert.equal(series.points[0].weightKg, 78.5);
  });

  await t.test('an unchanged resend does not add or move a log row', async () => {
    const userId = await makeUser(pool, 'resend@example.com');
    const { updateProfile } = require('../src/db/profile');
    const [[past]] = await pool.query(`SELECT ${daysAgo(5)} AS d`);
    await bw.writeEntry(pool, userId, { weightKg: 70, loggedOn: past.d });

    // A PATCH editing some unrelated field, with a client that still carries
    // the same weightKg it already had cached -- not a new weigh-in.
    await updateProfile(pool, userId, { fullName: 'Same Weight', weightKg: 70 });

    const [rows] = await pool.query(
      'SELECT log_date FROM body_weight_logs WHERE user_id = ?', [userId],
    );
    assert.equal(rows.length, 1, 'no new row was added for an unchanged resend');
  });

  await t.test('an out-of-range weight in a profile edit persists nothing', async () => {
    const userId = await makeUser(pool, 'invalid-weight@example.com');
    await pool.query('UPDATE users SET weight_kg = 70 WHERE user_id = ?', [userId]);
    const { updateProfile } = require('../src/db/profile');

    await assert.rejects(
      () => updateProfile(pool, userId, { weightKg: 600 }),
      (err) => {
        assert.equal(err.code, 'WEIGHT_OUT_OF_RANGE');
        assert.equal(err.message, 'Enter a weight between 20 and 500 kg.');
        assert.deepEqual(err.details, [{ field: 'weightKg', min: 20, max: 500, unit: 'kg' }]);
        return true;
      },
    );

    const [[user]] = await pool.query(
      'SELECT weight_kg FROM users WHERE user_id = ?', [userId],
    );
    assert.equal(Number(user.weight_kg), 70, 'the prior weight was not overwritten');
  });

  const weightOf = async (userId) => {
    const [[user]] = await pool.query('SELECT weight_kg FROM users WHERE user_id = ?', [userId]);
    return user.weight_kg === null ? null : Number(user.weight_kg);
  };

  await t.test('deleteEntry is null when nothing matches, including another user\'s day', async () => {
    const userId = await makeUser(pool, 'del-none@example.com');
    const other = await makeUser(pool, 'del-other@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 70, loggedOn: '2026-03-01' });
    await bw.writeEntry(pool, other, { weightKg: 60, loggedOn: '2026-03-02' });
    await bw.writeEntry(pool, other, { weightKg: 61, loggedOn: '2026-03-03' });
    assert.equal(await bw.deleteEntry(pool, userId, '2026-03-02'), null);
    const [rows] = await pool.query('SELECT 1 FROM body_weight_logs WHERE user_id = ?', [other]);
    assert.equal(rows.length, 2);
  });

  await t.test('deleteEntry syncs users.weight_kg only when the newest day goes', async () => {
    const userId = await makeUser(pool, 'del-sync@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: '2026-03-01' });
    await bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: '2026-03-02' });
    await bw.writeEntry(pool, userId, { weightKg: 78, loggedOn: '2026-03-03' });
    // Not the log's newest value, so a sync on an older day would show.
    await pool.query('UPDATE users SET weight_kg = 77.7 WHERE user_id = ?', [userId]);

    const older = await bw.deleteEntry(pool, userId, '2026-03-01');
    assert.equal(older.weightKg, 77.7);
    assert.equal(await weightOf(userId), 77.7, 'an older day leaves it alone');

    const newest = await bw.deleteEntry(pool, userId, '2026-03-03');
    assert.deepEqual(newest, {
      deleted: { loggedOn: '2026-03-03', weightKg: 78 },
      start: { loggedOn: '2026-03-02', weightKg: 79 },
      entries: 1,
      weightKg: 79,
    });
    assert.equal(await weightOf(userId), 79, 'the newest remaining weigh-in');
  });

  await t.test('deleteEntry refuses the only weigh-in day', async () => {
    const userId = await makeUser(pool, 'del-only@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: '2026-03-01' });
    await assert.rejects(
      () => bw.deleteEntry(pool, userId, '2026-03-01'),
      (err) => err.code === 'ONLY_WEIGH_IN' && err.status === 409,
    );
    assert.equal(await weightOf(userId), 80);
  });

  // users.weight_kg is synced from the log, so a delete and a weigh-in by the
  // same user must run one after the other. Both take the users row first.
  await t.test('deleteEntry waits for the users row lock', async () => {
    const userId = await makeUser(pool, 'del-lock@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: '2026-03-01' });
    await bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: '2026-03-02' });
    const holder = await pool.getConnection();
    try {
      await holder.beginTransaction();
      await holder.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);
      const pending = bw.deleteEntry(pool, userId, '2026-03-01');
      await new Promise((r) => { setTimeout(r, 300); });
      const [still] = await pool.query(
        "SELECT 1 FROM body_weight_logs WHERE user_id = ? AND log_date = '2026-03-01'", [userId],
      );
      assert.equal(still.length, 1, 'the delete has not run while the row is held');
      await holder.commit();
      assert.equal((await pending).deleted.loggedOn, '2026-03-01');
    } finally {
      await holder.rollback();
      holder.release();
    }
  });

  // A new day's INSERT already waits on its foreign-key check of the users
  // row; re-logging an existing day has no INSERT, so only the lock holds it.
  await t.test('writeEntry waits for the users row lock before writing the log', async () => {
    const userId = await makeUser(pool, 'write-lock@example.com');
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: '2026-03-01' });
    await bw.writeEntry(pool, userId, { weightKg: 80, loggedOn: '2026-03-02' });
    const holder = await pool.getConnection();
    try {
      await holder.beginTransaction();
      await holder.query('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);
      const pending = bw.writeEntry(pool, userId, { weightKg: 79, loggedOn: '2026-03-02' });
      await new Promise((r) => { setTimeout(r, 300); });
      // A locking read that fails at once on any row the write has already
      // touched: it only succeeds while the write is still waiting.
      await holder.query(
        'SELECT 1 FROM body_weight_logs WHERE user_id = ? FOR UPDATE NOWAIT', [userId],
      );
      await holder.commit();
      assert.equal((await pending).loggedOn, '2026-03-02');
    } finally {
      await holder.rollback();
      holder.release();
    }
  });
});
