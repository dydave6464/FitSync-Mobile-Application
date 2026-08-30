'use strict';
const { createPool } = require('./pool');

// The eight chips the design specifies, in display order.
//
// Curated by hand, deliberately NOT derived from the catalogue. The upstream
// dataset tags only the load-bearing implement, so a barbell bench press is
// 'barbell' and a pull-up is 'body weight' — it has no tag for a bench, a
// pull-up bar, or "machines" as a category. Those three `name`s therefore do
// not exist in the catalogue and this seed creates them, with no exercises
// attached. See the design doc, sections 2 and 8.
//
// `name` is the catalogue row promoted to carry the chip: it keeps its name and
// its exercises and gains a display_name. `children` are catalogue rows absorbed
// into it and hidden from onboarding.
const OPTIONS = [
  { displayName: 'Barbell', name: 'barbell', children: ['ez barbell', 'olympic barbell', 'trap bar'] },
  { displayName: 'Dumbbells', name: 'dumbbell', children: [] },
  { displayName: 'Bench', name: 'bench', children: [] },
  { displayName: 'Pull-up bar', name: 'pull-up bar', children: [] },
  { displayName: 'Kettlebell', name: 'kettlebell', children: [] },
  { displayName: 'Bands', name: 'band', children: ['resistance band'] },
  { displayName: 'Machines', name: 'machines', children: ['cable', 'smith machine', 'leverage machine'] },
  { displayName: 'Bodyweight', name: 'body weight', children: [] },
];

// MySQL 8.0.46: the row-alias form. VALUES() is deprecated since 8.0.20.
//
// parent_equipment_id is reset to NULL so that demoting a chip to a child and
// later promoting it back cannot leave it parented to itself.
const UPSERT_OPTION = `
  INSERT INTO equipment (name, display_name, display_order, is_user_selectable)
  VALUES (?, ?, ?, 1) AS new
  ON DUPLICATE KEY UPDATE
    display_name        = new.display_name,
    display_order       = new.display_order,
    is_user_selectable  = 1,
    parent_equipment_id = NULL
`;

// A no-op when the catalogue has not been seeded yet — but nothing else ever
// re-runs this adoption, so that no-op is not safe, it is silent data loss:
// the catalogue seed (`npm run seed`) must run BEFORE this one. Running
// seed:equipment first leaves these children permanently unparented
// (parent_equipment_id stays NULL) until seed:equipment is re-run once the
// catalogue exists. `missingChildTags` on the return value is what makes that
// omission observable instead of silent; see scripts/seed-equipment.js.
const ADOPT_CHILD = `
  UPDATE equipment
     SET parent_equipment_id = ?, is_user_selectable = 0,
         display_name = NULL, display_order = NULL
   WHERE name = ?
`;

// Existing users selected raw catalogue rows. Those rows are no longer
// selectable, so without this the onboarding step renders their gear unticked
// and the next save silently discards it.
//
// INSERT IGNORE, not UPDATE: a user owning both 'cable' and 'smith machine'
// maps to Machines twice, and uq_user_equipment (user_id, equipment_id) would
// reject the second. IGNORE absorbs it; the sweep below then removes the
// originals along with anything that has no curated home at all.
const MOVE_TO_PARENT = `
  INSERT IGNORE INTO user_equipment (user_id, equipment_id)
    SELECT ue.user_id, e.parent_equipment_id
      FROM user_equipment ue
      JOIN equipment e ON e.equipment_id = ue.equipment_id
     WHERE e.parent_equipment_id IS NOT NULL
`;

const DROP_UNSELECTABLE = `
  DELETE ue FROM user_equipment ue
    JOIN equipment e ON e.equipment_id = ue.equipment_id
   WHERE e.is_user_selectable = 0
`;

async function seedEquipment(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    let inserted = 0;
    let updated = 0;
    let unchanged = 0;
    let adopted = 0;
    const missingChildTags = [];

    for (const [index, option] of OPTIONS.entries()) {
      // uq_equipment_name makes this idempotent without a pre-read.
      const [result] = await pool.query(
        UPSERT_OPTION, [option.name, option.displayName, index + 1],
      );
      // mysql2 enables CLIENT_FOUND_ROWS, which turns the documented
      // affectedRows === 0 for an unchanged match into a 1. insertId is the
      // only field that separates a genuine insert from that. Same reasoning
      // as seed-injuries.js.
      if (result.affectedRows === 2) updated += 1;
      else if (result.affectedRows === 1 && result.insertId > 0) inserted += 1;
      else unchanged += 1;

      const [[parent]] = await pool.query(
        'SELECT equipment_id FROM equipment WHERE name = ?', [option.name],
      );
      for (const child of option.children) {
        // ADOPT_CHILD is a plain UPDATE, so CLIENT_FOUND_ROWS makes
        // affectedRows report rows matched, not rows changed — it would stay
        // 1 forever, even once the child is already adopted. changedRows is
        // unaffected by that flag and reflects MySQL's actual "Changed:"
        // count, so it correctly goes to 0 on a no-op re-run.
        const [r] = await pool.query(ADOPT_CHILD, [parent.equipment_id, child]);
        if (r.changedRows > 0) adopted += 1;
        // affectedRows === 0 means the WHERE name = ? matched nothing — the
        // catalogue seed has not run yet, or this tag was renamed/removed
        // upstream. Either way it is exactly the case the comment above warns
        // about: this run cannot adopt what is not there, and nothing retries
        // it later on its own.
        if (r.affectedRows === 0) missingChildTags.push(child);
      }
    }

    const [moved] = await pool.query(MOVE_TO_PARENT);
    const [dropped] = await pool.query(DROP_UNSELECTABLE);

    return {
      inserted,
      updated,
      unchanged,
      adopted,
      movedSelections: moved.affectedRows,
      droppedSelections: dropped.affectedRows,
      total: OPTIONS.length,
      missingChildTags,
    };
  } finally {
    await pool.end();
  }
}

module.exports = { seedEquipment, OPTIONS };
