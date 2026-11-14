'use strict';

// Deterministic and offline: what every test and WEEK_READER_MODE=stub get.
// "stub busy" stands for a Groq failure.
async function read({ text }) {
  const lower = String(text).toLowerCase();
  if (lower.includes('stub busy')) return null;
  const minutes = lower.match(/(\d{1,3})\s*min/);
  return {
    splitStyle: lower.includes('ppl') ? 'push_pull_legs' : null,
    minutes: minutes ? Number(minutes[1]) : null,
    weekdays: [],
    daysPerWeek: null,
    injuries: lower.includes('knee') ? [{ name: 'Knee', side: null }] : [],
    mentionsGoal: false,
  };
}

module.exports = { read, model: 'stub' };
