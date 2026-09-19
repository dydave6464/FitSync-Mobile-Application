'use strict';
const analytics = require('./analytics');
const { summariseHistory, listHistory } = require('./sessions');
const bodyWeight = require('./body-weight');

/// The toggleable sections of a shared report, in the order the page draws
/// them. The summary header is not among them -- it is always captured.
const SECTIONS = ['volume', 'bodyWeight', 'muscles', 'sessions'];

/// Everything the report page will ever show, read once and frozen.
///
/// A section the user switched off is not fetched and not stored. Capturing it
/// and letting the page hide it would mean the row held data the user believed
/// they had withheld.
///
/// `muscles` is the Pro section. Without Pro it comes back null even when
/// asked for, matching GET /sessions/analytics, which sends a free user no
/// muscle numbers rather than numbers it asks the client not to draw.
async function buildReportSnapshot(pool, userId, { period, include, premium }) {
  const want = (section) => Boolean(include && include[section]);

  const [summary, volume, change, muscles, weight, sessions] = await Promise.all([
    summariseHistory(pool, userId, period),
    want('volume') ? analytics.readVolumeBuckets(pool, userId, period) : null,
    want('volume') ? analytics.readVolumeChange(pool, userId, period) : null,
    want('muscles') && premium
      ? analytics.readVolumeByMuscle(pool, userId, period)
      : null,
    want('bodyWeight') ? bodyWeight.readSeries(pool, userId, period) : null,
    want('sessions') ? listHistory(pool, userId, { page: 1, limit: 20 }) : null,
  ]);

  const adherence = await analytics.readAdherence(pool, userId, period);

  return {
    summary: { ...summary, adherence },
    volume: want('volume') ? { buckets: volume, change } : null,
    bodyWeight: weight,
    muscles,
    sessions: sessions ? sessions.sessions : null,
  };
}

module.exports = { buildReportSnapshot, SECTIONS };
