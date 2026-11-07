'use strict';
const { likePattern } = require('../lib/query-params');
const { NICHE_EQUIPMENT } = require('./seeds/normalize');

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

module.exports = { STATUSES, asAdminExercise, listAdminExercises };
