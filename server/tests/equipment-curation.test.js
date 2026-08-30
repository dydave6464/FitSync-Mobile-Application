'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');

test('equipment curation schema', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  await t.test('equipment carries the four curation columns', async () => {
    const [rows] = await pool.query(
      `SELECT column_name AS name, column_default AS def, is_nullable AS nullable
         FROM information_schema.columns
        WHERE table_schema = ? AND table_name = 'equipment'`,
      [testDbConfig().database],
    );
    const byName = new Map(rows.map((r) => [r.name, r]));
    for (const col of [
      'display_name', 'display_order', 'is_user_selectable', 'parent_equipment_id',
    ]) {
      assert.ok(byName.has(col), `equipment.${col} must exist`);
    }
    assert.equal(byName.get('is_user_selectable').nullable, 'NO');
    assert.equal(Number(byName.get('is_user_selectable').def), 0);
  });

  await t.test('a row the catalogue seed inserts is not selectable', async () => {
    // The catalogue seed writes (name) only. The DEFAULT is what keeps a new
    // upstream tag out of onboarding without anyone noticing.
    await pool.query("INSERT INTO equipment (name) VALUES ('kettlebell')");
    const [[row]] = await pool.query(
      "SELECT is_user_selectable AS sel FROM equipment WHERE name = 'kettlebell'",
    );
    assert.equal(Number(row.sel), 0);
  });

  await t.test('parent_equipment_id must reference a real row', async () => {
    await assert.rejects(
      () => pool.query('UPDATE equipment SET parent_equipment_id = 999999'),
      /foreign key|ER_NO_REFERENCED_ROW/i,
    );
  });
});

const { seedEquipment } = require('../src/db/seed-equipment');

// The catalogue tags this feature cares about, as the upstream dataset spells
// them. Inserted directly so the test does not need the real 1324-row seed.
const CATALOGUE = [
  'barbell', 'ez barbell', 'olympic barbell', 'trap bar', 'dumbbell',
  'kettlebell', 'band', 'resistance band', 'cable', 'smith machine',
  'leverage machine', 'body weight', 'medicine ball', 'assisted',
];

test('equipment curation seed', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());

  t.after(async () => {
    await dropAllTables(pool);
    await pool.end();
  });

  const resetCatalogue = async () => {
    await pool.query('DELETE FROM user_equipment');
    await pool.query('UPDATE equipment SET parent_equipment_id = NULL');
    await pool.query('DELETE FROM equipment');
    for (const name of CATALOGUE) {
      await pool.query('INSERT INTO equipment (name) VALUES (?)', [name]);
    }
  };

  const selectable = async () => {
    const [rows] = await pool.query(
      `SELECT display_name AS label FROM equipment
        WHERE is_user_selectable = 1 ORDER BY display_order`,
    );
    return rows.map((r) => r.label);
  };

  await t.test('offers exactly the eight chips the design specifies', async () => {
    await resetCatalogue();
    await seedEquipment(testDbConfig());
    assert.deepEqual(await selectable(), [
      'Barbell', 'Dumbbells', 'Bench', 'Pull-up bar',
      'Kettlebell', 'Bands', 'Machines', 'Bodyweight',
    ]);
  });

  await t.test('creates the three rows the dataset has no tag for', async () => {
    await resetCatalogue();
    await seedEquipment(testDbConfig());
    const [rows] = await pool.query(
      "SELECT name FROM equipment WHERE name IN ('bench','pull-up bar','machines')",
    );
    assert.equal(rows.length, 3, 'bench, pull-up bar and machines are created');
  });

  await t.test('absorbs the machine tags as hidden children', async () => {
    await resetCatalogue();
    await seedEquipment(testDbConfig());
    const [rows] = await pool.query(
      `SELECT c.name AS child FROM equipment c
         JOIN equipment p ON p.equipment_id = c.parent_equipment_id
        WHERE p.name = 'machines' AND c.is_user_selectable = 0
        ORDER BY c.name`,
    );
    assert.deepEqual(rows.map((r) => r.child),
      ['cable', 'leverage machine', 'smith machine']);
  });

  await t.test('leaves an unmapped catalogue tag alone and unselectable', async () => {
    await resetCatalogue();
    await seedEquipment(testDbConfig());
    const [[row]] = await pool.query(
      `SELECT is_user_selectable AS sel, parent_equipment_id AS parent
         FROM equipment WHERE name = 'medicine ball'`,
    );
    assert.equal(Number(row.sel), 0);
    assert.equal(row.parent, null);
  });

  await t.test('is idempotent', async () => {
    await resetCatalogue();
    const first = await seedEquipment(testDbConfig());
    assert.equal(first.adopted, 7, 'the first run absorbs all seven child tags');
    const [[before]] = await pool.query('SELECT COUNT(*) AS n FROM equipment');
    const second = await seedEquipment(testDbConfig());
    const [[after]] = await pool.query('SELECT COUNT(*) AS n FROM equipment');
    assert.equal(Number(after.n), Number(before.n), 'a re-run adds no rows');
    assert.equal(second.adopted, 0, 'a re-run adopts nothing new');
    assert.deepEqual(await selectable(), [
      'Barbell', 'Dumbbells', 'Bench', 'Pull-up bar',
      'Kettlebell', 'Bands', 'Machines', 'Bodyweight',
    ]);
  });

  await t.test('survives a catalogue re-seed', async () => {
    await resetCatalogue();
    await seedEquipment(testDbConfig());
    // What `seed-exercises.js` does to an existing row: name only.
    await pool.query(
      "INSERT INTO equipment (name) VALUES ('barbell') AS new "
      + 'ON DUPLICATE KEY UPDATE name = new.name',
    );
    const [[row]] = await pool.query(
      "SELECT display_name AS label, is_user_selectable AS sel "
      + "FROM equipment WHERE name = 'barbell'",
    );
    assert.equal(row.label, 'Barbell', 'curation is not clobbered by a re-seed');
    assert.equal(Number(row.sel), 1);
  });
});
