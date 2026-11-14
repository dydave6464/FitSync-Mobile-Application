'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { cleanReading } = require('../src/services/week-reader/clean');
const { createReadCache, createDailyLimit } = require('../src/services/week-reader/memory');
const groqClient = require('../src/services/week-reader/groq-client');
const stub = require('../src/services/week-reader/stub');

const INJURIES = [
  { injuryId: 1, name: 'Lower back', isLateral: false },
  { injuryId: 2, name: 'Knee', isLateral: true },
];

test('cleanReading keeps only what checks out', () => {
  const reading = cleanReading({
    splitStyle: 'push_pull_legs', minutes: 50, weekdays: [5, 1, 3, 3, 0, 8, 2.5],
    daysPerWeek: 3, injuries: [{ name: 'knee', side: 'left' }, { name: 'KNEE', side: 'right' },
      { name: 'Lower back', side: 'left' }, { name: 'Elbowz' }], mentionsGoal: true,
  }, { injuries: INJURIES });
  assert.deepEqual(reading, {
    splitStyle: 'push_pull_legs', sessionLengthMin: 45, requestedMinutes: 50,
    weekdays: [1, 3, 5], daysPerWeek: 3,
    injuries: [{ injuryId: 2, side: 'left' }, { injuryId: 1, side: null }],
    mentionsGoal: true, source: 'ai',
  });
});

test('cleanReading drops what does not', () => {
  assert.deepEqual(cleanReading({
    splitStyle: 'bro_split', minutes: 500, weekdays: 'mon', daysPerWeek: 9,
    injuries: [{ name: 'Knee', side: 'up' }], mentionsGoal: 'yes',
  }, { injuries: INJURIES }), {
    splitStyle: null, sessionLengthMin: null, requestedMinutes: null, weekdays: [],
    daysPerWeek: null, injuries: [{ injuryId: 2, side: null }], mentionsGoal: false, source: 'ai',
  });
});

test('cleanReading snaps lengths with ties to 45', () => {
  const len = (minutes) => cleanReading({ minutes }, { injuries: [] }).sessionLengthMin;
  assert.equal(len(30), 45);
  assert.equal(len(52), 45);
  assert.equal(len(53), 60);
  assert.equal(len(90), 60);
  assert.equal(len(0), null);
  assert.equal(len(45.5), null);
});

test('cleanReading refuses a reply with the wrong shape', () => {
  assert.equal(cleanReading(null, { injuries: [] }), null);
  assert.equal(cleanReading([], { injuries: [] }), null);
  assert.equal(cleanReading('ppl', { injuries: [] }), null);
});

test('the cache answers the same sentence and forgets after a day', () => {
  let now = 0;
  const cache = createReadCache({ max: 2, ttlMs: 1000, now: () => now });
  cache.set('a', { x: 1 });
  assert.deepEqual(cache.get('a'), { x: 1 });
  now = 1001;
  assert.equal(cache.get('a'), undefined);
  cache.set('a', 1); cache.set('b', 2); cache.set('c', 3);
  assert.equal(cache.get('a'), undefined, 'the oldest entry goes when full');
  assert.equal(cache.get('c'), 3);
});

test('the daily limit counts per user per Manila day', () => {
  let now = Date.parse('2026-11-14T15:00:00Z'); // 23:00 Manila
  const limit = createDailyLimit({ perDay: 2, now: () => now });
  assert.equal(limit.hasRoom(1), true);
  limit.count(1); limit.count(1);
  assert.equal(limit.hasRoom(1), false);
  assert.equal(limit.hasRoom(2), true, 'another user has their own count');
  now = Date.parse('2026-11-14T16:00:00Z'); // 00:00 Manila, the next day
  assert.equal(limit.hasRoom(1), true);
});

test('the Groq client asks once with JSON mode, low effort and the small model', async () => {
  let sent;
  const fetchImpl = async (url, init) => {
    sent = { url, body: JSON.parse(init.body), auth: init.headers.authorization };
    return { ok: true, json: async () => ({ choices: [{ finish_reason: 'stop',
      message: { content: '{"splitStyle":"upper_lower","minutes":60}' } }] }) };
  };
  const client = groqClient.create({ apiKey: 'k', fetchImpl });
  const raw = await client.read({ text: 'upper lower, an hour', injuryNames: ['Knee'] });
  assert.deepEqual(raw, { splitStyle: 'upper_lower', minutes: 60 });
  assert.equal(sent.body.model, 'openai/gpt-oss-20b');
  assert.deepEqual(sent.body.response_format, { type: 'json_object' });
  assert.equal(sent.body.reasoning_effort, 'low');
  assert.equal(sent.body.messages[1].content, 'upper lower, an hour');
  assert.match(sent.body.messages[0].content, /Knee/);
  assert.equal(sent.auth, 'Bearer k');
});

test('the Groq client answers null for every failure', async () => {
  const failing = [
    async () => ({ ok: false, status: 429 }),
    async () => { throw new Error('ECONNRESET'); },
    async () => ({ ok: true, json: async () => ({ choices: [{ finish_reason: 'length', message: { content: '{' } }] }) }),
    async () => ({ ok: true, json: async () => ({ choices: [{ finish_reason: 'stop', message: { content: 'not json' } }] }) }),
  ];
  for (const fetchImpl of failing) {
    const client = groqClient.create({ apiKey: 'k', fetchImpl });
    assert.equal(await client.read({ text: 'ppl', injuryNames: [] }), null);
  }
});

test('the stub reads a few fixed phrases offline', async () => {
  assert.deepEqual(await stub.read({ text: 'PPL, 50 min, my knee' }),
    { splitStyle: 'push_pull_legs', minutes: 50, weekdays: [], daysPerWeek: null,
      injuries: [{ name: 'Knee', side: null }], mentionsGoal: false });
  assert.equal(await stub.read({ text: 'stub busy' }), null);
});

test('the off reader answers null for every sentence, so the route says AI_BUSY', async () => {
  const { offWeekReader } = require('../src/services/week-reader');
  assert.equal(offWeekReader.model, 'off');
  assert.equal(await offWeekReader.read({ text: 'upper lower mon wed fri', injuryNames: ['Knee'] }), null);
});
