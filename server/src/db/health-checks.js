'use strict';

/// The checklist's values, in the order the app shows them. The SET column in
/// migration 030 accepts exactly these.
const CONDITIONS = Object.freeze([
  'high_blood_pressure', 'heart_condition', 'diabetes', 'asthma',
  'pregnancy', 'recent_surgery', 'other',
]);

// UNIX_TIMESTAMP on a TIMESTAMP column hands back the stored UTC instant
// without a session time-zone conversion; see getProfile in db/profile.js.
function toIso(epoch) {
  return epoch == null ? null : new Date(Number(epoch) * 1000).toISOString();
}

/// mysql2 returns a SET column as one comma-joined string ('' when empty).
function toConditions(raw) {
  const stored = String(raw || '').split(',').filter(Boolean);
  return CONDITIONS.filter((c) => stored.includes(c));
}

async function readHealthCheck(pool, userId) {
  const [rows] = await pool.query(
    `SELECT conditions, chest_pain, dizziness, supervised_only,
            UNIX_TIMESTAMP(consented_at) AS consented_epoch,
            UNIX_TIMESTAMP(acknowledged_at) AS acknowledged_epoch
       FROM health_checks WHERE user_id = ?`, [userId],
  );
  if (rows.length === 0) return null;
  const r = rows[0];
  return {
    conditions: toConditions(r.conditions),
    chestPain: Boolean(r.chest_pain),
    dizziness: Boolean(r.dizziness),
    supervisedOnly: Boolean(r.supervised_only),
    consentedAt: toIso(r.consented_epoch),
    acknowledgedAt: toIso(r.acknowledged_epoch),
  };
}

/// Upserts the (already validated) answers. A positive check stamps consent
/// and acknowledgement now; a clear one stores both as NULL.
async function writeHealthCheck(pool, userId, answers) {
  const { conditions, chestPain, dizziness, supervisedOnly, positive } = answers;
  await pool.query(
    `INSERT INTO health_checks
       (user_id, conditions, chest_pain, dizziness, supervised_only,
        consented_at, acknowledged_at)
     VALUES (?, ?, ?, ?, ?, IF(?, CURRENT_TIMESTAMP, NULL), IF(?, CURRENT_TIMESTAMP, NULL))
     ON DUPLICATE KEY UPDATE
       conditions = VALUES(conditions),
       chest_pain = VALUES(chest_pain),
       dizziness = VALUES(dizziness),
       supervised_only = VALUES(supervised_only),
       consented_at = VALUES(consented_at),
       acknowledged_at = VALUES(acknowledged_at)`,
    [userId, conditions.join(','), chestPain, dizziness, supervisedOnly, positive, positive],
  );
  return readHealthCheck(pool, userId);
}

async function deleteHealthCheck(pool, userId) {
  await pool.query('DELETE FROM health_checks WHERE user_id = ?', [userId]);
}

module.exports = { CONDITIONS, readHealthCheck, writeHealthCheck, deleteHealthCheck };
