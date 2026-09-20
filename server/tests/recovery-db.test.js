'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  upsertCheckin, todayCheckin, recentCheckins, saveEstimate, latestEstimate,
  CHECKIN_SCALES,
} = require('../src/db/recovery');

const ANSWERS = {
  sleepQuality: 'good',
  muscleSoreness: 'mild',
  energy: 'moderate',
  stress: 'low',
};

async function freshUser(pool, email) {
  const [res] = await pool.query(
    `INSERT INTO users (email, password_hash, full_name)
     VALUES (?, 'x', 'Test User')`,
    [email],
  );
  return res.insertId;
}

test('recovery db', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  await t.test('a check-in is stored and read back for today', async () => {
    const userId = await freshUser(pool, 'rec-one@example.com');
    const saved = await upsertCheckin(pool, userId, ANSWERS);

    assert.ok(saved.checkinId > 0);
    assert.equal(saved.sleepQuality, 'good');

    const today = await todayCheckin(pool, userId);
    assert.equal(today.checkinId, saved.checkinId);
    assert.equal(today.muscleSoreness, 'mild');
  });

  await t.test('checking in twice in a day updates rather than duplicates',
    async () => {
      const userId = await freshUser(pool, 'rec-twice@example.com');
      const first = await upsertCheckin(pool, userId, ANSWERS);
      const second = await upsertCheckin(pool, userId, {
        ...ANSWERS, muscleSoreness: 'severe',
      });

      assert.equal(second.checkinId, first.checkinId);
      assert.equal((await todayCheckin(pool, userId)).muscleSoreness, 'severe');

      const [[{ n }]] = await pool.query(
        'SELECT COUNT(*) AS n FROM morning_checkins WHERE user_id = ?', [userId],
      );
      assert.equal(n, 1);
    });

  await t.test('recentCheckins answers camelCase keys and enum values',
    async () => {
      const userId = await freshUser(pool, 'rec-recent@example.com');
      await upsertCheckin(pool, userId, ANSWERS);

      const [row] = await recentCheckins(pool, userId);
      // These exact spellings are what risk.py looks up; anything else scores
      // zero penalty there without raising.
      assert.deepEqual(Object.keys(row).sort(), [
        'checkinDate', 'checkinId', 'energy', 'muscleSoreness',
        'sleepQuality', 'stress',
      ]);
      assert.equal(row.sleepQuality, 'good');
    });

  await t.test('the newest estimate is the one read back', async () => {
    const userId = await freshUser(pool, 'rec-est@example.com');
    const checkin = await upsertCheckin(pool, userId, ANSWERS);

    assert.equal(await latestEstimate(pool, userId), null);

    await saveEstimate(pool, {
      userId, checkinId: checkin.checkinId, riskLevel: 'low', trainingLoadScore: 12.5,
    });
    await saveEstimate(pool, {
      userId, checkinId: checkin.checkinId, riskLevel: 'moderate', trainingLoadScore: 44.25,
    });

    const latest = await latestEstimate(pool, userId);
    assert.equal(latest.riskLevel, 'moderate');
    assert.equal(latest.trainingLoadScore, 44.25);
    assert.match(latest.checkinDate, /^\d{4}-\d{2}-\d{2}$/);
  });

  await t.test('the scales match the columns', async () => {
    assert.deepEqual(CHECKIN_SCALES.sleepQuality,
      ['poor', 'fair', 'good', 'excellent']);
    assert.deepEqual(CHECKIN_SCALES.muscleSoreness,
      ['none', 'mild', 'moderate', 'severe']);
    assert.deepEqual(CHECKIN_SCALES.energy,
      ['very_low', 'low', 'moderate', 'high']);
    assert.deepEqual(CHECKIN_SCALES.stress,
      ['very_low', 'low', 'moderate', 'high']);
  });
});
