'use strict';
const AppError = require('./app-error');

// The one image rule: Snap a meal's photos and the admin's ad images.
const MAX_IMAGE_BYTES = 1_500_000;
const MAGIC = {
  'image/jpeg': [0xff, 0xd8, 0xff],
  'image/png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
};
const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png' };
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

const badImage = (message) => AppError.badRequest('INVALID_IMAGE', message);

/// Throws INVALID_IMAGE unless the body holds a JPEG or PNG -- by its first
/// bytes, not only its label -- of at most 1.5 MB; answers its decoded bytes
/// and file extension. Decoded into memory only; nothing here writes it
/// anywhere. [noun] names the image in the messages ('photo' for Snap a meal,
/// 'image' for an ad).
function checkImage(body, { noun = 'photo' } = {}) {
  const { image, mimeType } = body || {};
  const magic = Object.hasOwn(MAGIC, mimeType) ? MAGIC[mimeType] : null;
  if (!magic) throw badImage('mimeType must be image/jpeg or image/png.');
  if (typeof image !== 'string' || image.length === 0 || image.length % 4 !== 0 || !BASE64.test(image)) {
    throw badImage('image must be base64, with no data: prefix.');
  }
  const tooBig = `The ${noun} must be at most 1.5 MB.`;
  // The encoded length first, so an oversized image is refused undecoded.
  if (image.length > Math.ceil(MAX_IMAGE_BYTES / 3) * 4) throw badImage(tooBig);
  const bytes = Buffer.from(image, 'base64');
  if (bytes.length > MAX_IMAGE_BYTES) throw badImage(tooBig);
  if (!magic.every((b, i) => bytes[i] === b)) throw badImage(`The ${noun} is not the image type it says it is.`);
  return { bytes, ext: EXT[mimeType] };
}

module.exports = { checkImage, MAX_IMAGE_BYTES };
