'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  NICHE_EQUIPMENT,
  shouldPromote,
  storageKeys,
  normalizeRecord,
  isGif,
  isJpeg,
} = require('../src/db/seeds/normalize');

const RECORD = {
  id: '0001',
  name: '3/4 sit-up',
  category: 'waist',
  body_part: 'waist',
  equipment: 'body weight',
  target: 'abs',
  muscle_group: 'hip flexors',
  gif_url: 'videos/0001-2gPfomN.gif',
  image: 'images/0001-2gPfomN.jpg',
  instruction_steps: { en: ['Lie flat on your back.', 'Curl forward.'], tr: ['Yat.'] },
};

test('a record maps onto exactly the columns the schema has', () => {
  const out = normalizeRecord(RECORD);
  assert.deepEqual(out, {
    source_id: '0001',
    name: '3/4 sit-up',
    muscle_group: 'abs',
    equipment: 'body weight',
    animation_url: 'exercises/0001/animation.gif',
    thumbnail_url: 'exercises/0001/thumb.jpg',
    promote: true,
    cues: ['Lie flat on your back.', 'Curl forward.'],
  });
});

test('muscle_group comes from target, not the dataset field of the same name', () => {
  // The dataset's own "muscle_group" holds synergists; "target" is the primary
  // muscle, which is what the schema column means.
  assert.equal(normalizeRecord(RECORD).muscle_group, 'abs');
});

test('only English cues are kept', () => {
  assert.deepEqual(normalizeRecord(RECORD).cues, ['Lie flat on your back.', 'Curl forward.']);
});

test('an exercise with no English steps normalises to an empty cue list', () => {
  const out = normalizeRecord({ ...RECORD, instruction_steps: { tr: ['Yat.'] } });
  assert.deepEqual(out.cues, []);
});

test('storage keys are derived from source_id, not the upstream filename', () => {
  assert.deepEqual(storageKeys('0042'), {
    animation: 'exercises/0042/animation.gif',
    thumbnail: 'exercises/0042/thumb.jpg',
  });
});

test('ordinary equipment is promoted', () => {
  for (const equipment of ['body weight', 'dumbbell', 'barbell', 'cable', 'smith machine']) {
    assert.equal(shouldPromote({ ...RECORD, equipment }), true, equipment);
  }
});

test('the 14 niche equipment types stay pending', () => {
  assert.equal(NICHE_EQUIPMENT.size, 14);
  for (const equipment of NICHE_EQUIPMENT) {
    assert.equal(shouldPromote({ ...RECORD, equipment }), false, equipment);
  }
});

test('cardio stays pending whatever the equipment', () => {
  assert.equal(shouldPromote({ ...RECORD, body_part: 'cardio', equipment: 'body weight' }), false);
});

test('a valid GIF is accepted and anything else is rejected', () => {
  assert.equal(isGif(Buffer.from('GIF89a and then frames')), true);
  assert.equal(isGif(Buffer.from('GIF87a and then frames')), true);
  assert.equal(isGif(Buffer.from('<!DOCTYPE html><html>429</html>')), false, 'an error page');
  assert.equal(isGif(Buffer.alloc(0)), false, 'an empty response');
  assert.equal(isGif(Buffer.from('GIF')), false, 'a truncated response');
});

test('a valid JPEG is accepted and anything else is rejected', () => {
  assert.equal(isJpeg(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00])), true);
  assert.equal(isJpeg(Buffer.from('<!DOCTYPE html>')), false);
  assert.equal(isJpeg(Buffer.alloc(0)), false);
});
