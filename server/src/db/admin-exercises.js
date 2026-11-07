'use strict';
const AppError = require('../lib/app-error');
const { likePattern } = require('../lib/query-params');
const { NICHE_EQUIPMENT } = require('./seeds/normalize');
const { classifyCategory } = require('./classify-categories');
const { classifyRequirements } = require('./classify-requirements');
const { classifyContraindications } = require('./classify-contraindications');

const STATUSES = ['pending', 'live'];

const SELECT_EXERCISE = `
  SELECT x.exercise_id, x.name, x.muscle_group, x.body_part, x.status,
         x.thumbnail_url, x.animation_url, eq.name AS equipment
    FROM exercises x
    LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id`;

/// Why the seed held a pending exercise back (normalize.js's shouldPromote):
/// cardio, or equipment few trainees have. null for a live exercise, or a
/// pending one held back for neither (unpublished by an admin).
function pendingReason(row) {
  if (row.status !== 'pending') return null;
  if (row.body_part === 'cardio') return 'cardio';
  if (row.equipment && NICHE_EQUIPMENT.has(row.equipment)) return 'rare_equipment';
  return null;
}

/// A row of SELECT_EXERCISE in Appendix A's admin exercise shape. [toUrl]
/// turns a storage key into a URL (the database stores keys, as GET
/// /exercises does).
function asAdminExercise(row, toUrl) {
  return {
    id: row.exercise_id,
    name: row.name,
    muscleGroup: row.muscle_group,
    equipment: row.equipment,
    thumbnailUrl: toUrl(row.thumbnail_url),
    animationUrl: toUrl(row.animation_url),
    status: row.status,
    pendingReason: pendingReason(row),
  };
}

/// One page of the [status] exercises whose name matches [q], by name, with
/// the filtered total and the whole catalogue's pending and live counts
/// (the chips' numbers, which don't follow the search).
async function listAdminExercises(pool, { status, q = null, page = 1, limit = 30 }) {
  const where = ['x.status = ?'];
  const params = [status];
  if (q !== null && q.trim() !== '') {
    where.push('x.name LIKE ?');
    params.push(likePattern(q));
  }
  const whereSql = where.join(' AND ');

  const [[{ total }]] = await pool.query(`SELECT COUNT(*) AS total FROM exercises x WHERE ${whereSql}`, params);
  // exercise_id breaks ties: the catalogue has duplicate names.
  const [rows] = await pool.query(
    `${SELECT_EXERCISE} WHERE ${whereSql} ORDER BY x.name, x.exercise_id LIMIT ? OFFSET ?`,
    [...params, limit, (page - 1) * limit],
  );
  const [[counts]] = await pool.query(
    `SELECT COALESCE(SUM(status = 'pending'), 0) AS pending, COALESCE(SUM(status = 'live'), 0) AS live
       FROM exercises`,
  );
  return {
    rows,
    counts: { pending: Number(counts.pending), live: Number(counts.live) },
    total: Number(total),
  };
}

/// One exercise as SELECT_EXERCISE reads it, or null.
async function findAdminExercise(db, exerciseId) {
  const [[row]] = await db.query(`${SELECT_EXERCISE} WHERE x.exercise_id = ?`, [exerciseId]);
  return row || null;
}

function unclassifiable() {
  return AppError.conflict(
    'EXERCISE_UNCLASSIFIABLE',
    "This exercise's safety rules couldn't be worked out, so it can't be published.",
  );
}

/// [names]' ids in [table] by lower-cased name ({ id column, name column }),
/// or null when any name has no row: a safety row is never silently dropped.
async function idsByName(conn, table, idColumn, names) {
  if (names.length === 0) return [];
  const [rows] = await conn.query(`SELECT ${idColumn} AS id, name FROM ${table}`);
  const byName = new Map(rows.map((r) => [r.name.toLowerCase(), r.id]));
  const ids = names.map((name) => byName.get(name.toLowerCase()));
  return ids.includes(undefined) ? null : ids;
}

/// Sets a pending exercise live, reviewed by [adminId], with the category,
/// equipment-requirement and injury-contraindication rows the seed scripts
/// would write for it (the same pure classifiers, is_manual = 0), in one
/// transaction. A human's rows (is_manual = 1) are kept as they are. A
/// classifier naming equipment or an injury region the database lacks
/// refuses the whole publish (409 EXERCISE_UNCLASSIFIABLE): nothing changes.
/// A live exercise is answered unchanged; an unknown one is null.
async function publishExercise(pool, exerciseId, adminId) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    // The classifiers' input shape, as seed-exercise-safety.js reads it.
    const [[exercise]] = await conn.query(
      `SELECT x.exercise_id, x.name, x.muscle_group, x.body_part, x.status, eq.name AS equipment
         FROM exercises x
         LEFT JOIN equipment eq ON eq.equipment_id = x.equipment_id
        WHERE x.exercise_id = ?
        FOR UPDATE`,
      [exerciseId],
    );
    if (!exercise) {
      await conn.rollback();
      return null;
    }
    if (exercise.status === 'pending') {
      const contraindications = classifyContraindications(exercise);
      const equipmentIds = await idsByName(conn, 'equipment', 'equipment_id', classifyRequirements(exercise));
      const injuryIds = await idsByName(conn, 'injuries', 'injury_id', contraindications.map((row) => row.region));
      if (equipmentIds === null || injuryIds === null) throw unclassifiable();

      // exercise_id is the primary key: a human's category stays as it is.
      await conn.query(
        `INSERT INTO exercise_categories (exercise_id, category, is_manual) VALUES (?, ?, 0)
         ON DUPLICATE KEY UPDATE category = IF(is_manual = 1, category, VALUES(category))`,
        [exerciseId, classifyCategory(exercise)],
      );
      // IGNORE: a row already there (a human's, or one from an earlier
      // publish) holds the unique key and is kept.
      if (equipmentIds.length > 0) {
        await conn.query(
          'INSERT IGNORE INTO exercise_equipment_requirements (exercise_id, equipment_id, is_manual) VALUES ?',
          [equipmentIds.map((id) => [exerciseId, id, 0])],
        );
      }
      if (injuryIds.length > 0) {
        await conn.query(
          'INSERT IGNORE INTO exercise_contraindications (exercise_id, injury_id, pattern, is_manual) VALUES ?',
          [injuryIds.map((id, i) => [exerciseId, id, contraindications[i].pattern, 0])],
        );
      }
      await conn.query(
        "UPDATE exercises SET status = 'live', reviewed_by = ? WHERE exercise_id = ?",
        [adminId, exerciseId],
      );
    }
    const row = await findAdminExercise(conn, exerciseId);
    await conn.commit();
    return row;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  STATUSES, asAdminExercise, listAdminExercises, publishExercise,
};
