'use strict';
const { createPool } = require('./pool');
const { classifyRequirements } = require('./classify-requirements');
const { classifyContraindications } = require('./classify-contraindications');

// Reads every live exercise, recomputes its safety rows, and reconciles the
// tables to match. Rows with is_manual = 1 are a human's judgement and are
// never written or deleted here.
//
// Reconciliation is delete-then-insert against the computed set rather than a
// plain upsert, so that editing a classifier removes rows it no longer
// produces. Deleting a classifier row by hand therefore restores it on the next
// run -- for a safety table that is the correct direction to fail. To override,
// insert a row with is_manual = 1, or change the classifier.

const LIVE_EXERCISES = `
  SELECT x.exercise_id, x.name, x.muscle_group, x.body_part, eq.name AS equipment
    FROM exercises x
    LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id
   WHERE x.status = 'live'
`;

async function reconcile(pool, table, keyColumns, computed, existing) {
  const keyOf = (row) => keyColumns.map((c) => row[c]).join(' ');
  const wanted = new Map(computed.map((r) => [keyOf(r), r]));
  const have = new Map(existing.map((r) => [keyOf(r), r]));

  let removed = 0;
  for (const [key, row] of have) {
    if (wanted.has(key)) continue;
    await pool.query(
      `DELETE FROM ${table} WHERE ${keyColumns.map((c) => `${c} = ?`).join(' AND ')}
        AND is_manual = 0`,
      keyColumns.map((c) => row[c]),
    );
    removed += 1;
  }

  let inserted = 0;
  for (const [key, row] of wanted) {
    if (have.has(key)) continue;
    const columns = Object.keys(row);
    await pool.query(
      `INSERT INTO ${table} (${columns.join(', ')})
       VALUES (${columns.map(() => '?').join(', ')})`,
      columns.map((c) => row[c]),
    );
    inserted += 1;
  }
  return { inserted, removed };
}

async function seedExerciseSafety(dbConfig) {
  const pool = createPool(dbConfig);
  try {
    const [exercises] = await pool.query(LIVE_EXERCISES);
    const [equipmentRows] = await pool.query('SELECT equipment_id, name FROM equipment');
    const equipmentByName = new Map(
      equipmentRows.map((r) => [r.name.toLowerCase(), r.equipment_id]),
    );
    const [injuryRows] = await pool.query('SELECT injury_id, name FROM injuries');
    const injuryByName = new Map(
      injuryRows.map((r) => [r.name.toLowerCase(), r.injury_id]),
    );

    const unknownEquipment = new Set();
    const unknownRegions = new Set();
    const wantedRequirements = [];
    const wantedContraindications = [];

    for (const exercise of exercises) {
      for (const name of classifyRequirements(exercise)) {
        const equipmentId = equipmentByName.get(name);
        // seed-equipment.js may not have run yet, or the option was renamed.
        // Reporting beats a foreign-key crash that abandons the whole run.
        if (!equipmentId) { unknownEquipment.add(name); continue; }
        wantedRequirements.push({
          exercise_id: exercise.exercise_id, equipment_id: equipmentId,
        });
      }
      for (const row of classifyContraindications(exercise)) {
        const injuryId = injuryByName.get(row.region.toLowerCase());
        // Same reasoning as above, but the stakes are higher: a dropped
        // contraindication is a safety row that silently never existed.
        if (!injuryId) { unknownRegions.add(row.region); continue; }
        wantedContraindications.push({
          exercise_id: exercise.exercise_id,
          injury_id: injuryId,
          pattern: row.pattern,
        });
      }
    }

    const [existingReq] = await pool.query(
      'SELECT exercise_id, equipment_id FROM exercise_equipment_requirements WHERE is_manual = 0',
    );
    const [existingContra] = await pool.query(
      'SELECT exercise_id, injury_id FROM exercise_contraindications WHERE is_manual = 0',
    );

    // A manual row occupies the unique key, so never try to insert over it.
    const manualKeys = async (table, columns) => {
      const [rows] = await pool.query(
        `SELECT ${columns.join(', ')} FROM ${table} WHERE is_manual = 1`,
      );
      return new Set(rows.map((r) => columns.map((c) => r[c]).join(' ')));
    };
    const blockedReq = await manualKeys(
      'exercise_equipment_requirements', ['exercise_id', 'equipment_id'],
    );
    const blockedContra = await manualKeys(
      'exercise_contraindications', ['exercise_id', 'injury_id'],
    );

    const requirements = await reconcile(
      pool, 'exercise_equipment_requirements', ['exercise_id', 'equipment_id'],
      wantedRequirements.filter((r) => !blockedReq.has(`${r.exercise_id} ${r.equipment_id}`)),
      existingReq,
    );
    const contraindications = await reconcile(
      pool, 'exercise_contraindications', ['exercise_id', 'injury_id'],
      wantedContraindications.filter(
        (r) => !blockedContra.has(`${r.exercise_id} ${r.injury_id}`),
      ),
      existingContra,
    );

    return {
      requirements: { ...requirements, manual: blockedReq.size },
      contraindications: { ...contraindications, manual: blockedContra.size },
      unknownEquipment: [...unknownEquipment],
      unknownRegions: [...unknownRegions],
    };
  } finally {
    await pool.end();
  }
}

module.exports = { seedExerciseSafety };
