'use strict';
const { toNumber, SUMMARY_WINDOWS } = require('./sessions');

/// How many points each period's volume line has.
///
/// A fixed count per period is what makes this chart look like a chart on day
/// one: the buckets are ZERO-FILLED, and a week with no training genuinely IS
/// zero volume, so a flat stretch is truthful rather than a gap.
///
/// Bucket width is derived, not stored: ceil(days / count). For a year that
/// is 31 days across 12 buckets, slightly over the 365-day window, so the
/// oldest bucket covers fewer real days than the rest. Harmless -- it holds
/// less data, not wrong data -- and the alternative is fractional-day
/// arithmetic in SQL for a chart 84 pixels tall.
const BUCKETS = {
  week: { count: 7 },
  month: { count: 6 },
  year: { count: 12 },
};

/// Volume per bucket, oldest first, always `count` entries long.
async function readVolumeBuckets(pool, userId, period = 'week') {
  const days = SUMMARY_WINDOWS[period];
  const shape = BUCKETS[period];
  if (!days || !shape) return null;

  const width = Math.ceil(days / shape.count);

  // Bucket 0 is the most recent `width` days; the reverse below puts oldest
  // first, which is the direction a chart reads.
  //
  // LEAST(..., shape.count - 1) clamps the index so an out-of-range bucket is
  // structurally impossible. With the correct `>` above, daysAgo never
  // reaches `days`, so the raw FLOOR() never reaches `count` and LEAST never
  // binds -- this changes nothing in correct operation. It exists purely as
  // a guard: a `>=` here once let a session dated exactly `days` ago into
  // this query, where its bucket index landed one past the array the output
  // loop reads, and its volume vanished without a trace -- not zero-filled,
  // not merged, just gone. If that boundary is ever wrong again, LEAST folds
  // the stray session into the OLDEST bucket instead of dropping it: visible
  // data in a slightly wrong period beats data that silently disappears.
  const [rows] = await pool.query(
    `SELECT LEAST(FLOOR(DATEDIFF(CURDATE(), s.session_date) / ?), ?) AS bucket,
            COALESCE(SUM(s.total_volume_kg), 0) AS volume_kg
       FROM workout_sessions s
      WHERE s.user_id = ? AND s.status = 'completed'
        AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
      GROUP BY bucket`,
    [width, shape.count - 1, userId, days],
  );

  const byBucket = new Map(rows.map((r) => [Number(r.bucket), toNumber(r.volume_kg) ?? 0]));

  const out = [];
  for (let i = shape.count - 1; i >= 0; i -= 1) {
    out.push({
      label: bucketLabel(i, width),
      volumeKg: byBucket.get(i) ?? 0,
    });
  }
  return out;
}

/// What the x-axis prints. Days for a week, "Nw"/"Nm" ago otherwise -- a date
/// under every point would collide at six labels, let alone twelve.
function bucketLabel(index, width) {
  if (width === 1) return index === 0 ? 'today' : `-${index}d`;
  if (width <= 7) return index === 0 ? 'now' : `-${index * width}d`;
  return index === 0 ? 'now' : `-${index}m`;
}

/// Sessions completed against the active plan's target for the same window.
///
/// `weeks` rounds the window to whole weeks (1, 4, 52) and the COUNT uses
/// `weeks * 7` days rather than the raw window, so numerator and denominator
/// describe the same stretch of time. Counting 30 days of sessions against a
/// 4-week target lets a diligent user score 17/16, and a ratio above 100%
/// reads as a bug rather than as praise.
///
/// No active plan means no target, and the card then shows the count alone.
/// The plan is what defines the target; one invented without it is fiction.
async function readAdherence(pool, userId, period = 'week') {
  const days = SUMMARY_WINDOWS[period];
  if (!days) return null;

  const weeks = Math.round(days / 7);

  const [[plan]] = await pool.query(
    `SELECT days_per_week FROM workout_plans
      WHERE user_id = ? AND is_active = TRUE
      ORDER BY plan_id DESC LIMIT 1`,
    [userId],
  );

  const [[row]] = await pool.query(
    `SELECT COUNT(*) AS done FROM workout_sessions
      WHERE user_id = ? AND status = 'completed'
        AND session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)`,
    [userId, weeks * 7],
  );

  return {
    done: Number(row.done),
    target: plan ? plan.days_per_week * weeks : null,
    weeks,
  };
}

/// Completed sets per muscle group, largest first.
///
/// Sets rather than kilograms, deliberately. Volume is dominated by exercise
/// selection -- a leg press outweighs a set of pull-ups by 8,000 kg to zero,
/// because bodyweight work has no `weight_kg` at all -- while a set is a set.
async function readSetsByMuscle(pool, userId, period = 'week') {
  const days = SUMMARY_WINDOWS[period];
  if (!days) return null;

  const [rows] = await pool.query(
    `SELECT e.muscle_group AS muscle, COUNT(*) AS sets
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE s.user_id = ? AND s.status = 'completed'
        AND sl.is_completed = TRUE
        AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
      GROUP BY e.muscle_group
      ORDER BY sets DESC, muscle ASC`,
    [userId, days],
  );

  return rows.map((r) => ({ muscle: r.muscle, sets: Number(r.sets) }));
}

/// This window's volume against the one immediately before it.
///
/// The number the mockup's `+12%` tag was reaching for, and the only honest
/// thing volume has to say. The TOTAL is meaningless -- nobody has intuition
/// for 48,200 kg, and it swings by 50x between Week and Year -- but the
/// DIRECTION is real, which is why volume survives as a trend rather than as
/// the headline it used to be.
///
/// `changePct` is null when the previous window held nothing. A first week has
/// nothing to be up against, and "+100%" measured from zero is not a fact
/// about training.
async function readVolumeChange(pool, userId, period = 'week') {
  const days = SUMMARY_WINDOWS[period];
  if (!days) return null;

  const [[row]] = await pool.query(
    `SELECT
       COALESCE(SUM(CASE WHEN s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
                         THEN s.total_volume_kg END), 0) AS current_kg,
       COALESCE(SUM(CASE WHEN s.session_date <= DATE_SUB(CURDATE(), INTERVAL ? DAY)
                         THEN s.total_volume_kg END), 0) AS previous_kg
       FROM workout_sessions s
      WHERE s.user_id = ? AND s.status = 'completed'
        AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)`,
    [days, days, userId, days * 2],
  );

  const totalKg = toNumber(row.current_kg) ?? 0;
  const previousKg = toNumber(row.previous_kg) ?? 0;

  return {
    totalKg,
    previousKg,
    changePct: previousKg === 0
      ? null
      : Math.round(((totalKg - previousKg) / previousKg) * 100),
  };
}

module.exports = {
  readVolumeBuckets,
  readVolumeChange,
  readAdherence,
  readSetsByMuscle,
  BUCKETS,
};
