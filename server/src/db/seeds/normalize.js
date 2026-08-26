'use strict';

// Equipment a FitSync user is not expected to own or meet in a typical gym.
// Exercises using it stay 'pending' for an admin review pass; they are still
// seeded, so nothing is lost. See the design doc, section 8.
const NICHE_EQUIPMENT = new Set([
  'assisted',
  'bosu ball',
  'elliptical machine',
  'hammer',
  'roller',
  'rope',
  'skierg machine',
  'sled machine',
  'stationary bike',
  'stepmill machine',
  'tire',
  'upper body ergometer',
  'weighted',
  'wheel roller',
]);

function shouldPromote(record) {
  return record.body_part !== 'cardio' && !NICHE_EQUIPMENT.has(record.equipment);
}

function storageKeys(sourceId) {
  return {
    animation: `exercises/${sourceId}/animation.gif`,
    thumbnail: `exercises/${sourceId}/thumb.jpg`,
  };
}

function normalizeRecord(record) {
  const keys = storageKeys(record.id);
  return {
    source_id: record.id,
    name: record.name,
    // The dataset also has a field literally called muscle_group, but it holds
    // synergist muscles. `target` is the primary muscle, which is what the
    // exercises.muscle_group column means.
    muscle_group: record.target,
    equipment: record.equipment,
    animation_url: keys.animation,
    thumbnail_url: keys.thumbnail,
    promote: shouldPromote(record),
    cues: (record.instruction_steps && record.instruction_steps.en) || [],
  };
}

const GIF89A = Buffer.from('GIF89a', 'ascii');
const GIF87A = Buffer.from('GIF87a', 'ascii');
const JPEG_SOI = Buffer.from([0xff, 0xd8, 0xff]);

// A rate-limit page, a redirect body or a truncated download all arrive as a
// 200 with bytes in it. Checking the magic number is what separates real media
// from those before anything reaches storage.
function isGif(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 6) return false;
  const head = buffer.subarray(0, 6);
  return head.equals(GIF89A) || head.equals(GIF87A);
}

function isJpeg(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 3) return false;
  return buffer.subarray(0, 3).equals(JPEG_SOI);
}

module.exports = {
  NICHE_EQUIPMENT,
  shouldPromote,
  storageKeys,
  normalizeRecord,
  isGif,
  isJpeg,
};
