'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const {
  upsertCheckin, todayCheckin, recentCheckins, saveEstimate, latestEstimate,
  reportedInjuries, worstRecentPain, CHECKIN_SCALES, RECENT_PAIN_DAYS,
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

async function region(pool, name, group) {
  const [res] = await pool.query(
    'INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, ?)',
    [name, group],
  );
  return res.insertId;
}

/// A completed session [daysAgo] days before today with one pain report.
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

  await t.test('reportedInjuries answers the profile injuries as plan refs, and only this user\'s',
    async () => {
      const knee = await region(pool, 'Knee (db test)', 'lower_body');
      const wrist = await region(pool, 'Wrist (db test)', 'upper_body');
      const userId = await freshUser(pool, 'rec-inj@example.com');
      const other = await freshUser(pool, 'rec-inj-other@example.com');
      await pool.query(
        "INSERT INTO user_injuries (user_id, injury_id, side) VALUES (?, ?, 'left')",
        [userId, knee],
      );
      await pool.query(
        'INSERT INTO user_injuries (user_id, injury_id) VALUES (?, ?)', [other, wrist],
      );

      assert.deepEqual(await reportedInjuries(pool, userId), [
        { injuryId: knee, regionGroup: 'lower_body' },
      ]);
      assert.deepEqual(await reportedInjuries(pool, await freshUser(pool, 'rec-inj-none@example.com')), []);
    });

  await t.test('worstRecentPain is null with no reports', async () => {
    const userId = await freshUser(pool, 'rec-pain-none@example.com');
    assert.equal(await worstRecentPain(pool, userId), null);
  });

  await t.test('worstRecentPain takes the worst level inside the window', async () => {
    assert.equal(RECENT_PAIN_DAYS, 14);
    const back = await region(pool, 'Lower back (db test)', 'back');
    const userId = await freshUser(pool, 'rec-pain-worst@example.com');
    await painReport(pool, userId, 1, 'mild', back);
    await painReport(pool, userId, 3, 'moderate', back);
    await painReport(pool, userId, 5, 'none', null);
    assert.equal(await worstRecentPain(pool, userId), 'moderate');
  });

  await t.test('a "none" report is a report: it answers none, not null', async () => {
    const userId = await freshUser(pool, 'rec-pain-zero@example.com');
    await painReport(pool, userId, 2, 'none', null);
    assert.equal(await worstRecentPain(pool, userId), 'none');
  });

  await t.test('the 14-day window keeps day 13 and drops day 14', async () => {
    const neck = await region(pool, 'Neck (db test)', 'upper_body');
    const inside = await freshUser(pool, 'rec-pain-13@example.com');
    await painReport(pool, inside, 13, 'severe', neck);
    assert.equal(await worstRecentPain(pool, inside), 'severe');

    const outside = await freshUser(pool, 'rec-pain-14@example.com');
    await painReport(pool, outside, 14, 'severe', neck);
    assert.equal(await worstRecentPain(pool, outside), null);
  });

  await t.test('the window ends today: a session dated in the future is not counted', async () => {
    const hip = await region(pool, 'Hip (db test)', 'lower_body');
    const userId = await freshUser(pool, 'rec-pain-future@example.com');
    await painReport(pool, userId, 0, 'mild', hip);
    await painReport(pool, userId, -1, 'severe', hip);
    assert.equal(await worstRecentPain(pool, userId), 'mild');
  });

  await t.test('another user\'s pain is never read', async () => {
    const elbow = await region(pool, 'Elbow (db test)', 'upper_body');
    const userId = await freshUser(pool, 'rec-pain-mine@example.com');
    const other = await freshUser(pool, 'rec-pain-theirs@example.com');
    await painReport(pool, other, 1, 'severe', elbow);
    assert.equal(await worstRecentPain(pool, userId), null);
    await painReport(pool, userId, 1, 'mild', elbow);
    assert.equal(await worstRecentPain(pool, userId), 'mild');
  });

  await t.test('an estimate\'s source, version, load and drivers are stored and read back',
    async () => {
      const userId = await freshUser(pool, 'rec-drivers@example.com');
      const checkin = await upsertCheckin(pool, userId, ANSWERS);
      const drivers = [
        { key: 'load', value: 35 },
        { key: 'sleep', value: 'poor' },
        { key: 'injury_history', value: 2 },
      ];
      await saveEstimate(pool, {
        userId,
        checkinId: checkin.checkinId,
        riskLevel: 'moderate',
        trainingLoadScore: 47.25,
        source: 'model',
        modelVersion: 'risk-rf-sim-1',
        loadPct: 35,
        drivers,
      });

      const latest = await latestEstimate(pool, userId);
      assert.equal(latest.source, 'model');
      assert.equal(latest.loadPct, 35);
      assert.deepEqual(latest.drivers, drivers);

      const [[row]] = await pool.query(
        'SELECT model_version FROM injury_risk_estimates WHERE user_id = ?', [userId],
      );
      assert.equal(row.model_version, 'risk-rf-sim-1');
    });

  await t.test('an empty drivers list is stored as one, not as nothing', async () => {
    const userId = await freshUser(pool, 'rec-drivers-empty@example.com');
    const checkin = await upsertCheckin(pool, userId, ANSWERS);
    await saveEstimate(pool, {
      userId, checkinId: checkin.checkinId, riskLevel: 'low', trainingLoadScore: 10,
      source: 'rules', modelVersion: null, loadPct: 0, drivers: [],
    });
    const [[row]] = await pool.query(
      'SELECT drivers, load_pct FROM injury_risk_estimates WHERE user_id = ?', [userId],
    );
    assert.notEqual(row.drivers, null);
    assert.equal(Number(row.load_pct), 0);
    assert.deepEqual((await latestEstimate(pool, userId)).drivers, []);
  });

  await t.test('an estimate from before 037 reads as null source and load, and no drivers',
    async () => {
      const userId = await freshUser(pool, 'rec-old-row@example.com');
      const checkin = await upsertCheckin(pool, userId, ANSWERS);
      await pool.query(
        `INSERT INTO injury_risk_estimates (user_id, checkin_id, risk_level, training_load_score)
         VALUES (?, ?, 'low', 12.5)`,
        [userId, checkin.checkinId],
      );
      const latest = await latestEstimate(pool, userId);
      assert.equal(latest.riskLevel, 'low');
      assert.equal(latest.source, null);
      assert.equal(latest.loadPct, null);
      assert.deepEqual(latest.drivers, []);
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
