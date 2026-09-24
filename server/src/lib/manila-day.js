'use strict';

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

/// YYYY-MM-DD in Manila, `daysBack` days before `now`.
///
/// The same day MySQL's CURDATE() gives, now that every pooled connection
/// runs at +08:00 (see db/pool.js), so a caption built here agrees with data
/// windowed there. Fixed-offset arithmetic rather than the host's local
/// getters: those follow whatever zone the server machine is set to. The
/// Philippines keeps no daylight saving, so +08:00 is always exact.
function manilaDay(daysBack = 0, now = new Date()) {
  const d = new Date(now.getTime() + MANILA_OFFSET_MS);
  d.setUTCDate(d.getUTCDate() - daysBack);
  return d.toISOString().slice(0, 10);
}

module.exports = { manilaDay };
