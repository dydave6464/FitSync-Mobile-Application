'use strict';
const { toNumber, periodDays } = require('./sessions');

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
  const days = periodDays(period);
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
/// The COUNT and the target cover the same N days -- the window every reader
/// here uses, the N calendar days ending today -- and the target is the
/// plan's days_per_week spread over them, rounded: 3 a week is 13 over 30
/// days. Counting over a different span than the target describes is what
/// once let a diligent user score 17/16.
///
/// `weeks` (1, 4, 52) is kept in the response for the client's model; the
/// arithmetic no longer uses it.
///
/// No active plan means no target, and the card then shows the count alone.
/// The plan is what defines the target; one invented without it is fiction.
async function readAdherence(pool, userId, period = 'week') {
  const days = periodDays(period);
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
    [userId, days],
  );

  return {
    done: Number(row.done),
    target: plan ? Math.round((plan.days_per_week * days) / 7) : null,
    weeks,
  };
}

/// Completed sets per muscle group, largest first.
///
/// Sets rather than kilograms, deliberately. Volume is dominated by exercise
/// selection -- a leg press outweighs a set of pull-ups by 8,000 kg to zero,
/// because bodyweight work has no `weight_kg` at all -- while a set is a set.
/// Kilograms lifted per muscle group in the window.
///
/// Volume is `SUM(weight_kg * reps)`, the same measure `total_volume_kg`
/// carries per session (see completeSession in src/db/sessions.js) and the
/// volume-trend card already sums -- so the two cards on the Progress tab
/// cannot disagree about what a kilogram of work is.
///
/// A set is not a unit of effort: five sets of 20 kg and five of 100 kg draw
/// the same bar under a COUNT, which is what this replaced.
///
/// HAVING excludes a muscle group worked only without external load: a
/// bodyweight set stores no weight, so its SUM is NULL, and `NULL > 0` is
/// not true. Omitting the row entirely is the honest rendering -- a zero bar
/// would read as "this muscle was not worked" when it was, just not in a way
/// volume can describe.
async function readVolumeByMuscle(pool, userId, period = 'week') {
  const days = periodDays(period);
  if (!days) return null;

  const [rows] = await pool.query(
    `SELECT e.muscle_group AS muscle, SUM(sl.weight_kg * sl.reps) AS volume_kg
       FROM set_logs sl
       JOIN workout_sessions s ON s.session_id = sl.session_id
       JOIN exercises e ON e.exercise_id = sl.exercise_id
      WHERE s.user_id = ? AND s.status = 'completed'
        AND sl.is_completed = TRUE
        AND s.session_date > DATE_SUB(CURDATE(), INTERVAL ? DAY)
      GROUP BY e.muscle_group
      HAVING volume_kg > 0
      ORDER BY volume_kg DESC, muscle ASC`,
    [userId, days],
  );

  return rows.map((r) => ({ muscle: r.muscle, volumeKg: Number(r.volume_kg) }));
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
  const days = periodDays(period);
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
  readVolumeByMuscle,
  BUCKETS,
};
