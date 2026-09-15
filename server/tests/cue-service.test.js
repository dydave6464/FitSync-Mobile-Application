'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createCueService } = require('../src/services/cues');
const { parseReply, create } = require('../src/services/cues/groq-client');

const REQUEST = {
  exerciseName: 'Overhead Press',
  muscleGroup: 'delts',
  injuryName: 'Shoulder',
  reason: 'shoulder_load',
};

const GOOD_CUES = [
  { title: 'Stop the bar at your forehead', detail: 'Past that the joint takes the load.' },
  { title: 'Control the lowering', detail: 'Two seconds down.' },
];

/// A fetch that answers however the test needs, so the failure contract can be
/// exercised without a network. The real client takes this by injection for
/// exactly that reason.
function fakeFetch(answer) {
  return async () => {
    if (answer instanceof Error) throw answer;
    return answer;
  };
}

function okResponse(content) {
  return {
    ok: true,
    json: async () => ({ choices: [{ message: { content } }] }),
  };
}

test('choosing a cue service', async (t) => {
  await t.test('defaults to the stub, which makes no network call', async () => {
    const service = createCueService({});
    const cues = await service.generate(REQUEST);

    assert.ok(Array.isArray(cues));
    assert.ok(cues.length >= 2 && cues.length <= 3);
    for (const cue of cues) {
      assert.equal(typeof cue.title, 'string');
      assert.equal(typeof cue.detail, 'string');
    }
  });

  // Tests assert on which injury reached the prompt, so the stub has to say.
  await t.test('the stub names the injury it was asked about', async () => {
    const service = createCueService({ mode: 'stub' });
    const cues = await service.generate(REQUEST);
    assert.match(cues[0].title, /Shoulder/);
  });

  await t.test('the stub reports a model, so a cached row can record one', () => {
    assert.equal(typeof createCueService({}).model, 'string');
  });

  // Fail at construction, not on the first workout.
  await t.test('groq mode without a key is refused up front', () => {
    assert.throws(() => createCueService({ mode: 'groq' }), /GROQ_API_KEY/);
  });

  await t.test('an unsupported mode is refused', () => {
    assert.throws(() => createCueService({ mode: 'wat' }), /CUES_MODE/);
  });
});

// The reply is untrusted input, and the table it lands in has no expiry -- a
// malformed generation stored once is stored forever.
test('validating a model reply', async (t) => {
  const valid = JSON.stringify({ cues: GOOD_CUES });

  await t.test('accepts a well-formed reply and trims it', () => {
    const padded = JSON.stringify({
      cues: [{ title: '  Stop at the ribs  ', detail: '  Two seconds down.  ' },
        { title: 'Brace first', detail: 'Ribs down.' }],
    });
    const cues = parseReply(padded);
    assert.equal(cues.length, 2);
    assert.equal(cues[0].title, 'Stop at the ribs');
    assert.equal(cues[0].detail, 'Two seconds down.');
  });

  await t.test('rejects anything unparseable', () => {
    for (const bad of ['not json', '', '   ', null, undefined, 42]) {
      assert.equal(parseReply(bad), null, `accepted ${JSON.stringify(bad)}`);
    }
  });

  await t.test('rejects the wrong shape', () => {
    const bad = [
      { cues: 'nope' },
      { tips: GOOD_CUES },
      { cues: [{ title: 'x' }, { title: 'y' }] },
      { cues: [{ detail: 'x' }, { detail: 'y' }] },
      { cues: [null, null] },
      { cues: [{ title: 1, detail: 2 }, { title: 3, detail: 4 }] },
    ];
    for (const shape of bad) {
      assert.equal(parseReply(JSON.stringify(shape)), null,
        `accepted ${JSON.stringify(shape)}`);
    }
  });

  await t.test('rejects an empty title or detail', () => {
    const blank = { cues: [{ title: '', detail: 'x' }, { title: 'y', detail: '  ' }] };
    assert.equal(parseReply(JSON.stringify(blank)), null);
  });

  await t.test('rejects too few and too many', () => {
    const one = { cues: [GOOD_CUES[0]] };
    const ten = { cues: Array.from({ length: 10 }, () => GOOD_CUES[0]) };
    assert.equal(parseReply(JSON.stringify(one)), null);
    assert.equal(parseReply(JSON.stringify(ten)), null);
    assert.equal(parseReply(JSON.stringify({ cues: [] })), null);
  });

  // The columns are VARCHAR(120) and VARCHAR(400). MySQL would truncate an
  // over-long cue mid-sentence rather than refuse it.
  await t.test('rejects a cue wider than its column', () => {
    const longTitle = { cues: [{ title: 'x'.repeat(121), detail: 'ok' }, GOOD_CUES[1]] };
    const longDetail = { cues: [{ title: 'ok', detail: 'y'.repeat(401) }, GOOD_CUES[1]] };
    assert.equal(parseReply(JSON.stringify(longTitle)), null);
    assert.equal(parseReply(JSON.stringify(longDetail)), null);
    // The exact width is accepted -- the cap is the column, not one below it.
    const exact = { cues: [{ title: 'x'.repeat(120), detail: 'y'.repeat(400) }, GOOD_CUES[1]] };
    assert.equal(parseReply(JSON.stringify(exact)).length, 2);
  });
});

// A workout is never blocked by Groq. Every failure resolves the same way:
// return null, and the caller serves the catalogue's own cues.
test('the groq client never throws', async (t) => {
  const client = (answer) => create({
    apiKey: 'k', model: 'test-model', fetchImpl: fakeFetch(answer),
  });

  await t.test('returns the cues on a good reply', async () => {
    const cues = await client(okResponse(JSON.stringify({ cues: GOOD_CUES })))
      .generate(REQUEST);
    assert.equal(cues.length, 2);
    assert.equal(cues[0].title, GOOD_CUES[0].title);
  });

  // A 429 is the free tier working as documented, not an incident.
  await t.test('a rate limit resolves to null', async () => {
    const cues = await client({ ok: false, status: 429, json: async () => ({}) })
      .generate(REQUEST);
    assert.equal(cues, null);
  });

  await t.test('a server error resolves to null', async () => {
    const cues = await client({ ok: false, status: 500, json: async () => ({}) })
      .generate(REQUEST);
    assert.equal(cues, null);
  });

  await t.test('a network failure resolves to null', async () => {
    const cues = await client(new Error('ECONNRESET')).generate(REQUEST);
    assert.equal(cues, null);
  });

  await t.test('an abort resolves to null', async () => {
    const abort = new Error('aborted');
    abort.name = 'AbortError';
    assert.equal(await client(abort).generate(REQUEST), null);
  });

  await t.test('a reply with no choices resolves to null', async () => {
    const cues = await client({ ok: true, json: async () => ({}) }).generate(REQUEST);
    assert.equal(cues, null);
  });

  await t.test('a malformed generation resolves to null', async () => {
    const cues = await client(okResponse('not json')).generate(REQUEST);
    assert.equal(cues, null);
  });

  await t.test('reports its model, for the cached row', () => {
    assert.equal(client(okResponse('{}')).model, 'test-model');
  });

  // The prompt is where the safety rules live. If the injury and the reason
  // never reach it, every cue is generic and the gate bought nothing.
  await t.test('sends the exercise, the injury and the reason', async () => {
    let sent = null;
    const spy = create({
      apiKey: 'k',
      fetchImpl: async (_url, options) => {
        sent = JSON.parse(options.body);
        return okResponse(JSON.stringify({ cues: GOOD_CUES }));
      },
    });
    await spy.generate(REQUEST);

    const user = sent.messages.find((m) => m.role === 'user').content;
    assert.match(user, /Overhead Press/);
    assert.match(user, /Shoulder/);
    assert.match(user, /shoulder_load/);

    const system = sent.messages.find((m) => m.role === 'system').content;
    assert.match(system, /never diagnose|Never diagnose/);
    assert.equal(sent.response_format.type, 'json_object');
  });
});
