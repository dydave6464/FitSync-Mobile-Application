'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('../src/config');
const { createVisionService } = require('../src/services/vision');
const groqClient = require('../src/services/vision/groq-client');
const { buildPrompt, parseReply } = require('../src/services/vision/prompt');
const { VisionError } = require('../src/services/vision/errors');

const ENV = { DB_HOST: 'h', DB_PORT: '3306', DB_USER: 'u', DB_PASSWORD: 'p', DB_NAME: 'n', JWT_SECRET: 'x'.repeat(32) };

test('config: VISION_MODE defaults to the stub and reuses GROQ_API_KEY', () => {
  assert.deepEqual(load(ENV).vision, { mode: 'stub', apiKey: null, model: null });
  assert.deepEqual(load({ ...ENV, VISION_MODE: 'groq', GROQ_API_KEY: 'k', VISION_MODEL: 'm' }).vision, { mode: 'groq', apiKey: 'k', model: 'm' });
});

test('createVisionService picks the driver', () => {
  assert.equal(createVisionService({}).model, 'stub');
  assert.throws(() => createVisionService({ mode: 'groq' }), /GROQ_API_KEY is required when VISION_MODE=groq/);
  assert.throws(() => createVisionService({ mode: 'gemini' }), /Unsupported VISION_MODE: gemini/);
  assert.equal(createVisionService({ mode: 'groq', apiKey: 'k' }).model, 'qwen/qwen3.8-27b');
  assert.equal(createVisionService({ mode: 'groq', apiKey: 'k', model: 'other/model' }).model, 'other/model');
});

test('the stub answers from the menu it is given, with one item not on it', async () => {
  const stub = createVisionService({});
  const { items } = await stub.recognize({ imageBase64: 'x', mimeType: 'image/jpeg', menuNames: ['White rice', 'Chicken adobo', 'Pork adobo'] });
  assert.deepEqual(items.map((i) => i.menu), ['White rice', 'Chicken adobo', null]);
  assert.deepEqual(items[1].alternatives, ['Pork adobo']);
  const none = await stub.recognize({ imageBase64: 'x', mimeType: 'image/jpeg', menuNames: [] });
  assert.deepEqual(none.items.map((i) => i.menu), [null]);
});

test('buildPrompt lists the menu one name per line and asks for alternatives', () => {
  const p = buildPrompt(['White rice', 'Sinigang na baboy']);
  assert.match(p, /MENU:\nWhite rice\nSinigang na baboy$/);
  assert.match(p, /A soup or stew is ONE item/);
  assert.match(p, /"alternatives"/);
  assert.match(p, /Reply with JSON only/);
});

test('parseReply keeps what it can read and refuses what it cannot', () => {
  assert.equal(parseReply('not json'), null);
  assert.equal(parseReply(''), null);
  assert.equal(parseReply('{"notes":"no items key"}'), null);
  assert.deepEqual(parseReply('{"items":[]}'), { items: [] });
  const r = parseReply(JSON.stringify({ items: [
    { menu: 'White rice', name: 'Rice', quantity: 1, unit: 'cup', grams: 150, confidence: 0.95, alternatives: ['Garlic fried rice (sinangag)', 7, ''] },
    { menu: null, name: 'Atchara', quantity: -1, unit: '', grams: 'lots', confidence: 3 },
    { menu: 'Pork adobo' },
    { quantity: 2 },
    'junk',
  ] }));
  assert.deepEqual(r.items, [
    { menu: 'White rice', name: 'Rice', quantity: 1, unit: 'cup', grams: 150, confidence: 0.95, alternatives: ['Garlic fried rice (sinangag)'] },
    { menu: null, name: 'Atchara', quantity: null, unit: null, grams: null, confidence: 1, alternatives: [] },
    { menu: 'Pork adobo', name: 'Pork adobo', quantity: null, unit: null, grams: null, confidence: null, alternatives: [] },
  ]);
});

/// A fetch that answers each call from [replies] in turn and records what it was sent.
function fakeFetch(replies) {
  const calls = [];
  const fn = async (url, opts) => {
    calls.push({ url, opts, body: JSON.parse(opts.body) });
    const r = replies[calls.length - 1];
    if (typeof r === 'function') return r(opts);
    return {
      ok: r.status >= 200 && r.status < 300,
      status: r.status,
      json: async () => ({ choices: [{ finish_reason: r.finish ?? 'stop', message: { content: r.content } }] }),
    };
  };
  fn.calls = calls;
  return fn;
}
const GOOD = JSON.stringify({ items: [{ menu: 'White rice', name: 'White rice', quantity: 1, unit: 'cup', grams: 160, confidence: 0.9, alternatives: [] }] });
const ARGS = { imageBase64: 'QUJD', mimeType: 'image/png', menuNames: ['White rice'] };

test('groq: sends the photo and the menu the way the spike did', async () => {
  const fetchImpl = fakeFetch([{ status: 200, content: GOOD }]);
  const vision = groqClient.create({ apiKey: 'secret-key', fetchImpl });
  const reply = await vision.recognize(ARGS);
  assert.equal(reply.items[0].menu, 'White rice');
  const { url, opts, body } = fetchImpl.calls[0];
  assert.equal(url, 'https://api.groq.com/openai/v1/chat/completions');
  assert.equal(opts.headers.authorization, 'Bearer secret-key');
  assert.equal(body.model, 'qwen/qwen3.8-27b');
  assert.equal(body.temperature, 0.2);
  assert.equal(body.reasoning_effort, 'none');
  assert.deepEqual(body.response_format, { type: 'json_object' });
  const [text, image] = body.messages[0].content;
  assert.equal(text.text, buildPrompt(['White rice']));
  assert.equal(image.image_url.url, 'data:image/png;base64,QUJD');
});

test('groq: an unreadable reply is asked once more; a second one fails', async () => {
  const retried = fakeFetch([{ status: 200, content: 'oops' }, { status: 200, content: GOOD }]);
  assert.equal((await groqClient.create({ apiKey: 'k', fetchImpl: retried }).recognize(ARGS)).items.length, 1);
  assert.equal(retried.calls.length, 2);

  const cut = fakeFetch([{ status: 200, content: GOOD, finish: 'length' }, { status: 200, content: GOOD }]);
  await groqClient.create({ apiKey: 'k', fetchImpl: cut }).recognize(ARGS);
  assert.equal(cut.calls.length, 2, 'a reply cut off at the token limit is not trusted');

  const twice = fakeFetch([{ status: 200, content: 'oops' }, { status: 200, content: '{"x":1}' }]);
  await assert.rejects(groqClient.create({ apiKey: 'k', fetchImpl: twice }).recognize(ARGS),
    (e) => e instanceof VisionError && e.code === 'VISION_UNAVAILABLE');
  assert.equal(twice.calls.length, 2);
});

test('groq: 429 is busy, 5xx and timeouts are unavailable, and neither is retried', async () => {
  const busy = fakeFetch([{ status: 429, content: '' }]);
  await assert.rejects(groqClient.create({ apiKey: 'k', fetchImpl: busy }).recognize(ARGS), (e) => e.code === 'VISION_BUSY');
  assert.equal(busy.calls.length, 1);

  const down = fakeFetch([{ status: 503, content: '' }]);
  await assert.rejects(groqClient.create({ apiKey: 'k', fetchImpl: down }).recognize(ARGS), (e) => e.code === 'VISION_UNAVAILABLE');
  assert.equal(down.calls.length, 1);

  const slow = fakeFetch([(opts) => new Promise((_, reject) => {
    opts.signal.addEventListener('abort', () => reject(new Error('aborted')));
  })]);
  await assert.rejects(groqClient.create({ apiKey: 'k', fetchImpl: slow, timeoutMs: 20 }).recognize(ARGS), (e) => e.code === 'VISION_UNAVAILABLE');
  assert.equal(slow.calls.length, 1);
});
