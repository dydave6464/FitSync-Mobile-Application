'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { REGIONS: CLASSIFIER_REGIONS } = require('../src/db/classify-contraindications');
const { REGIONS: SEEDED_REGIONS } = require('../src/db/seed-injuries');
const { OPTIONS: SEEDED_EQUIPMENT } = require('../src/db/seed-equipment');

// Pure vocabulary checks, no database. A classifier region or equipment name
// that drifts from the seed's list would otherwise surface only as a runtime
// "unknown" warning after rows had already been skipped -- these guard the
// seam directly.

test('every contraindication region the classifier can return is seeded by seed-injuries.js', () => {
  const seededNames = new Set(SEEDED_REGIONS.map((r) => r.name));
  for (const name of CLASSIFIER_REGIONS) {
    assert.ok(seededNames.has(name), `${name} is not in seed-injuries.js REGIONS`);
  }
  assert.equal(CLASSIFIER_REGIONS.length, SEEDED_REGIONS.length);
});

test('every curated equipment name the requirement classifier can return is seeded by seed-equipment.js', () => {
  const seededNames = new Set(SEEDED_EQUIPMENT.map((o) => o.name));
  for (const name of ['bench', 'pull-up bar', 'machines']) {
    assert.ok(seededNames.has(name), `${name} is not in seed-equipment.js OPTIONS`);
  }
});
