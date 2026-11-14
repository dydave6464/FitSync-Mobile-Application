'use strict';

/// In-memory, per server process: a restart forgets both. Fine for a cache
/// and a guard; neither is a record of anything.

function createReadCache({ max = 500, ttlMs = 24 * 60 * 60 * 1000, now = Date.now } = {}) {
  const entries = new Map();
  return {
    get(key) {
      const hit = entries.get(key);
      if (!hit) return undefined;
      if (now() - hit.at > ttlMs) { entries.delete(key); return undefined; }
      return hit.value;
    },
    set(key, value) {
      entries.delete(key);
      entries.set(key, { value, at: now() });
      if (entries.size > max) entries.delete(entries.keys().next().value);
    },
  };
}

const manilaDay = (ms) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Manila' }).format(ms);

function createDailyLimit({ perDay = 30, now = Date.now } = {}) {
  const counts = new Map();
  const key = (userId) => `${userId}:${manilaDay(now())}`;
  return {
    hasRoom: (userId) => (counts.get(key(userId)) ?? 0) < perDay,
    count(userId) {
      const k = key(userId);
      counts.set(k, (counts.get(k) ?? 0) + 1);
    },
  };
}

module.exports = { createReadCache, createDailyLimit };
