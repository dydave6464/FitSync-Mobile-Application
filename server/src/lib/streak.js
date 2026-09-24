'use strict';

const DAY_MS = 24 * 60 * 60 * 1000;

/// 'YYYY-MM-DD' -> whole days since 1970-01-01. UTC on both sides, so no host
/// zone or daylight-saving hour can move a date by one.
function dayNumber(date) {
  return Math.round(Date.parse(`${date}T00:00:00Z`) / DAY_MS);
}

function dateOf(dayNo) {
  return new Date(dayNo * DAY_MS).toISOString().slice(0, 10);
}

/// The streak for a set of active dates, as of [today] (both 'YYYY-MM-DD').
///
/// current: the unbroken run ending today -- or ending yesterday when today
/// has no activity yet, because today does not break a streak until it is
/// over. best: the longest run anywhere. week: Monday to Sunday of today's
/// week, a day after today never active.
function computeStreak(activeDates, today) {
  const active = new Set(activeDates.map(dayNumber));
  const todayNo = dayNumber(today);

  const end = active.has(todayNo) ? todayNo : todayNo - 1;
  let current = 0;
  while (active.has(end - current)) current += 1;

  let best = 0;
  for (const day of active) {
    if (active.has(day - 1)) continue; // not the first day of a run
    let run = 1;
    while (active.has(day + run)) run += 1;
    if (run > best) best = run;
  }

  // Day 0 (1970-01-01) was a Thursday: index 3 in a Monday-first week.
  const monday = todayNo - ((todayNo + 3) % 7);
  const week = [];
  for (let i = 0; i < 7; i += 1) {
    const day = monday + i;
    week.push({ date: dateOf(day), active: day <= todayNo && active.has(day) });
  }

  return { current, best, todayActive: active.has(todayNo), week };
}

module.exports = { computeStreak };
