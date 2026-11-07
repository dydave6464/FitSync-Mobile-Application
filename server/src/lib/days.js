'use strict';

/// True when [value] is a real calendar day written as YYYY-MM-DD.
///
/// A month or day out of range (2026-13-01) parses to an Invalid Date;
/// February 30th parses, rolls over to March, and fails the round trip.
function isRealDay(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

module.exports = { isRealDay };
