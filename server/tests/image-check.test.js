'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { checkImage, imageTypeOf, MAX_IMAGE_BYTES } = require('../src/lib/image-check');

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d]);
const b64 = (buf) => buf.toString('base64');

/// The INVALID_IMAGE message checkImage throws for [body], or fails.
function refusal(body, opts) {
  try {
    checkImage(body, opts);
  } catch (err) {
    assert.equal(err.status, 400);
    assert.equal(err.code, 'INVALID_IMAGE');
    return err.message;
  }
  assert.fail('checkImage accepted the body');
}

test('checkImage', async (t) => {
  await t.test('a JPEG or PNG passes and answers its bytes and extension', () => {
    assert.deepEqual(checkImage({ image: b64(JPEG), mimeType: 'image/jpeg' }), { bytes: JPEG, ext: 'jpg' });
    assert.deepEqual(checkImage({ image: b64(PNG), mimeType: 'image/png' }), { bytes: PNG, ext: 'png' });
  });

  await t.test('a missing or unknown mimeType is refused', () => {
    assert.equal(refusal({ image: b64(JPEG) }), 'mimeType must be image/jpeg or image/png.');
    assert.equal(refusal({ image: b64(JPEG), mimeType: 'image/gif' }), 'mimeType must be image/jpeg or image/png.');
    assert.equal(refusal(undefined), 'mimeType must be image/jpeg or image/png.');
  });

  await t.test('bad base64 or a data: prefix is refused', () => {
    const msg = 'image must be base64, with no data: prefix.';
    assert.equal(refusal({ image: `data:image/jpeg;base64,${b64(JPEG)}`, mimeType: 'image/jpeg' }), msg);
    assert.equal(refusal({ image: '', mimeType: 'image/jpeg' }), msg);
    assert.equal(refusal({ image: 'abc', mimeType: 'image/jpeg' }), msg);
    assert.equal(refusal({ image: 42, mimeType: 'image/jpeg' }), msg);
  });

  await t.test('bytes that are not the type the label says are refused', () => {
    assert.equal(refusal({ image: b64(PNG), mimeType: 'image/jpeg' }), 'The photo is not the image type it says it is.');
    assert.equal(refusal({ image: b64(JPEG), mimeType: 'image/png' }), 'The photo is not the image type it says it is.');
  });

  await t.test('over 1,500,000 bytes is refused; exactly 1,500,000 passes', () => {
    const big = Buffer.alloc(1_500_001);
    JPEG.copy(big);
    assert.equal(refusal({ image: b64(big), mimeType: 'image/jpeg' }), 'The photo must be at most 1.5 MB.');
    const max = Buffer.alloc(1_500_000);
    JPEG.copy(max);
    assert.equal(checkImage({ image: b64(max), mimeType: 'image/jpeg' }).bytes.length, 1_500_000);
  });

  await t.test("noun 'image' names an image, not a photo", () => {
    const big = Buffer.alloc(1_500_001);
    JPEG.copy(big);
    const opts = { noun: 'image' };
    assert.equal(refusal({ image: b64(big), mimeType: 'image/jpeg' }, opts), 'The image must be at most 1.5 MB.');
    assert.equal(refusal({ image: b64(PNG), mimeType: 'image/jpeg' }, opts), 'The image is not the image type it says it is.');
  });
});

// The same rule for bytes read from disk (the dish photo import).
test('imageTypeOf', async (t) => {
  await t.test('a JPEG or PNG answers its type and extension', () => {
    assert.deepEqual(imageTypeOf(JPEG), { mime: 'image/jpeg', ext: 'jpg' });
    assert.deepEqual(imageTypeOf(PNG), { mime: 'image/png', ext: 'png' });
  });

  await t.test('anything else, or too big, answers null', () => {
    assert.equal(imageTypeOf(Buffer.from('GIF89a')), null);
    assert.equal(imageTypeOf(Buffer.alloc(0)), null);
    assert.equal(imageTypeOf(PNG.subarray(0, 4)), null);
    assert.equal(imageTypeOf('not a buffer'), null);
    const atLimit = Buffer.concat([JPEG, Buffer.alloc(MAX_IMAGE_BYTES - JPEG.length)]);
    assert.deepEqual(imageTypeOf(atLimit), { mime: 'image/jpeg', ext: 'jpg' });
    assert.equal(imageTypeOf(Buffer.concat([atLimit, Buffer.alloc(1)])), null);
  });
});
