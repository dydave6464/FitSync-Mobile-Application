'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('injury-risk drivers schema (037)', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const [u] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('drivers@b.com', 'x', 'D')",
  );
  const [c] = await pool.query(
    `INSERT INTO morning_checkins
       (user_id, checkin_date, sleep_quality, muscle_soreness, energy, stress)
     VALUES (?, CURDATE(), 'poor', 'mild', 'low', 'high')`,
    [u.insertId],
  );

  await t.test('an estimate written without the new columns leaves them NULL', async () => {
    const [e] = await pool.query(
      `INSERT INTO injury_risk_estimates (user_id, checkin_id, risk_level, training_load_score)
       VALUES (?, ?, 'low', 12.5)`,
      [u.insertId, c.insertId],
    );
    const [[row]] = await pool.query(
      `SELECT source, model_version, load_pct, drivers
         FROM injury_risk_estimates WHERE estimate_id = ?`,
      [e.insertId],
    );
    assert.deepEqual(
      [row.source, row.model_version, row.load_pct, row.drivers],
      [null, null, null, null],
    );
  });

  await t.test('source, model version, load and drivers read back as written', async () => {
    const drivers = [{ key: 'load', value: 130 }, { key: 'sleep', value: 'poor' }];
    const [e] = await pool.query(
      `INSERT INTO injury_risk_estimates
         (user_id, checkin_id, risk_level, training_load_score,
          source, model_version, load_pct, drivers)
       VALUES (?, ?, 'high', 71.5, 'model', ?, 130, ?)`,
      [u.insertId, c.insertId, 'x'.repeat(40), JSON.stringify(drivers)],
    );
    const [[row]] = await pool.query(
      `SELECT source, model_version, load_pct, drivers
         FROM injury_risk_estimates WHERE estimate_id = ?`,
      [e.insertId],
    );
    assert.equal(row.source, 'model');
    assert.equal(row.model_version, 'x'.repeat(40));
    assert.equal(Number(row.load_pct), 130);
    const parsed = typeof row.drivers === 'string' ? JSON.parse(row.drivers) : row.drivers;
    assert.deepEqual(parsed, drivers);
  });

  await t.test('a source other than model or rules is refused', async () => {
    await assert.rejects(() => pool.query(
      `INSERT INTO injury_risk_estimates (user_id, checkin_id, risk_level, source)
       VALUES (?, ?, 'low', 'guess')`,
      [u.insertId, c.insertId],
    ));
  });
});
