'use strict';

/// Groq's reply is untrusted text. Every field is checked against what the
/// app and the generator accept; anything else becomes null or is dropped.
/// A reply that is not an object is refused whole (null), which the route
/// answers as AI_BUSY.
const SPLIT_STYLES = ['full_body', 'push_pull_legs', 'upper_lower', 'cardio_core'];
const SIDES = ['left', 'right', 'both'];

// ML's _nearest_session_length: the nearest of 45 and 60, ties to 45.
const snapLength = (m) => (Math.abs(m - 45) <= Math.abs(m - 60) ? 45 : 60);
const wholeIn = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;

function cleanReading(raw, { injuries }) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;

  const minutes = wholeIn(raw.minutes, 1, 240) ? raw.minutes : null;
  const weekdays = Array.isArray(raw.weekdays)
    ? [...new Set(raw.weekdays.filter((d) => wholeIn(d, 1, 7)))].sort((a, b) => a - b)
    : [];

  const byName = new Map(injuries.map((i) => [i.name.toLowerCase(), i]));
  const picked = [];
  for (const item of Array.isArray(raw.injuries) ? raw.injuries : []) {
    const match = item && typeof item.name === 'string'
      ? byName.get(item.name.trim().toLowerCase()) : undefined;
    if (!match || picked.some((p) => p.injuryId === match.injuryId)) continue;
    picked.push({
      injuryId: match.injuryId,
      side: match.isLateral && SIDES.includes(item.side) ? item.side : null,
    });
  }

  return {
    splitStyle: SPLIT_STYLES.includes(raw.splitStyle) ? raw.splitStyle : null,
    sessionLengthMin: minutes === null ? null : snapLength(minutes),
    requestedMinutes: minutes,
    weekdays,
    daysPerWeek: wholeIn(raw.daysPerWeek, 1, 7) ? raw.daysPerWeek : null,
    injuries: picked,
    mentionsGoal: raw.mentionsGoal === true,
    source: 'ai',
  };
}

module.exports = { cleanReading, snapLength, SPLIT_STYLES };
