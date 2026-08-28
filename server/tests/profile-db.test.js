'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { seedInjuries } = require('../src/db/seed-injuries');
const {
  getProfile, updateProfile, setEquipment, setInjuries, listInjuries,
} = require('../src/db/profile');

test('profile queries', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  await seedInjuries(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  let userId;
  const reset = async () => {
    await pool.query('DELETE FROM user_injuries');
    await pool.query('DELETE FROM user_equipment');
    await pool.query('DELETE FROM users');
    const [r] = await pool.query(
      "INSERT INTO users (email, password_hash, full_name) VALUES ('p@example.com','x','P')",
    );
    userId = r.insertId;
  };

  await t.test('updates only the fields given', async () => {
    await reset();
    await updateProfile(pool, userId, { mainGoal: 'improve_endurance' });
    await updateProfile(pool, userId, { heightCm: 175 });
    const p = await getProfile(pool, userId);
    assert.equal(p.mainGoal, 'improve_endurance', 'the first write must survive the second');
    assert.equal(Number(p.heightCm), 175);
  });

  await t.test('an empty update is a no-op, not a crash', async () => {
    await reset();
    await updateProfile(pool, userId, {});
    assert.ok(await getProfile(pool, userId));
  });

  await t.test('equipment is replaced, not appended', async () => {
    await reset();
    await pool.query("INSERT INTO equipment (name) VALUES ('barbell'), ('dumbbell')");
    const [eq] = await pool.query('SELECT equipment_id FROM equipment ORDER BY equipment_id');
    await setEquipment(pool, userId, [eq[0].equipment_id, eq[1].equipment_id]);
    await setEquipment(pool, userId, [eq[1].equipment_id]);
    const p = await getProfile(pool, userId);
    assert.equal(p.equipment.length, 1, 'the set is replaced wholesale');
  });

  await t.test('injuries record a side, and non-lateral ones do not', async () => {
    await reset();
    const all = await listInjuries(pool);
    const knee = all.find((i) => i.name === 'Knee');
    const lowerBack = all.find((i) => i.name === 'Lower back');
    await setInjuries(pool, userId, [
      { injuryId: knee.injuryId, side: 'right' },
      { injuryId: lowerBack.injuryId, side: null },
    ]);
    const p = await getProfile(pool, userId);
    assert.equal(p.injuries.length, 2);
    assert.equal(p.injuries.find((i) => i.name === 'Knee').side, 'right');
    assert.equal(p.injuries.find((i) => i.name === 'Lower back').side, null);
  });

  await t.test('lookup exposes laterality and grouping', async () => {
    const all = await listInjuries(pool);
    assert.equal(all.find((i) => i.name === 'Knee').isLateral, true);
    assert.equal(all.find((i) => i.name === 'Neck').isLateral, false);
    assert.equal(all.find((i) => i.name === 'Knee').regionGroup, 'lower_body');
  });
});
