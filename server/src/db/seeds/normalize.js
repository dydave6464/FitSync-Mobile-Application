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

// Upstream equipment tags this project has judged wrong, keyed by source_id.
// Applied by seed-exercises.js as records leave the manifest for the database,
// so the vendored dataset stays a faithful copy of upstream and every
// correction we make is visible in one place.
//
// A wrong primary tag is not cosmetic: the candidate query filters on it, and
// the plan generator prefers exercises whose equipment the user actually
// selected during onboarding. A bodyweight movement mislabelled `dumbbell`
// therefore fills a dumbbell owner's plan with work their dumbbell does not do.
//
// '1274' deep push up -- tagged `dumbbell`, but its own instruction steps
// describe a plain bodyweight push-up: "Start in a high plank position with
// your hands slightly wider than shoulder-width apart... Push through your
// palms to extend your arms."
const EQUIPMENT_OVERRIDES = new Map([
  ['1274', 'body weight'],
]);

function correctEquipment(record) {
  return EQUIPMENT_OVERRIDES.get(String(record.source_id)) || record.equipment;
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
    // Coarser than `target` and unrelated to it: `target` is the muscle worked,
    // `body_part` is the region involved. Injury filtering needs the region.
    body_part: record.body_part,
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
  EQUIPMENT_OVERRIDES,
  correctEquipment,
  shouldPromote,
  storageKeys,
  normalizeRecord,
  isGif,
  isJpeg,
};
