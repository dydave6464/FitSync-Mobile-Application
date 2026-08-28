'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('auth schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const column = async (table, name) => {
    const [rows] = await pool.query(
      `SELECT IS_NULLABLE, COLUMN_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?`,
      [table, name],
    );
    return rows[0] || null;
  };

  await t.test('user_identities exists with a unique provider subject', async () => {
    const [rows] = await pool.query(
      `SELECT INDEX_NAME FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'user_identities'
          AND INDEX_NAME = 'uq_identity_provider_subject'`,
    );
    assert.ok(rows.length > 0, 'unique key on (provider, provider_subject) must exist');
  });

  await t.test('password_hash is nullable for Google-only accounts', async () => {
    const col = await column('users', 'password_hash');
    assert.equal(col.IS_NULLABLE, 'YES');
  });

  await t.test('main_goal offers improve_endurance, not gain_strength', async () => {
    const col = await column('users', 'main_goal');
    assert.match(col.COLUMN_TYPE, /improve_endurance/);
    assert.doesNotMatch(col.COLUMN_TYPE, /gain_strength/);
  });

  await t.test('users gains the onboarding and notification columns', async () => {
    assert.ok(await column('users', 'onboarding_completed_at'));
    assert.ok(await column('users', 'notifications_enabled'));
  });

  await t.test('injuries carry laterality and a group', async () => {
    assert.ok(await column('injuries', 'is_lateral'));
    assert.ok(await column('injuries', 'region_group'));
  });

  await t.test('user_injuries records a side', async () => {
    const col = await column('user_injuries', 'side');
    assert.match(col.COLUMN_TYPE, /left/);
    assert.equal(col.IS_NULLABLE, 'YES', 'non-lateral regions have no side');
  });

  await t.test('exercises keep body_part for injury filtering later', async () => {
    assert.ok(await column('exercises', 'body_part'));
  });
});
