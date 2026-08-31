'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyContraindications, isSpineSafe, REGIONS,
} = require('../src/db/classify-contraindications');

const ex = (name, muscleGroup, bodyPart) => ({
  name, muscle_group: muscleGroup, body_part: bodyPart,
});
const regions = (e) => classifyContraindications(e).map((r) => r.region).sort();
const blocks = (e, region) => regions(e).includes(region);

test('a deadlift is contraindicated for a back injury despite training glutes', () => {
  // The bug this table exists to fix: muscle_group says 'glutes', which is
  // lower_body, so a muscle-group filter alone would clear it for a back injury.
  const deadlift = ex('barbell deadlift', 'glutes', 'upper legs');
  assert.equal(isSpineSafe(deadlift), false);
  assert.ok(blocks(deadlift, 'Lower back'));
});

test('the spine allow-list covers Core as well as Lower back', () => {
  const deadlift = ex('barbell deadlift', 'glutes', 'upper legs');
  assert.ok(blocks(deadlift, 'Core'));
});

test('the other spinal-load movements are caught too', () => {
  for (const name of [
    'barbell romanian deadlift', 'barbell good morning', 'barbell bent-over row',
    'power clean', 'kettlebell one arm snatch', 'barbell front squat',
    'dumbbell farmer walk', 'barbell thruster',
  ]) {
    assert.equal(isSpineSafe(ex(name, 'glutes', 'upper legs')), false, name);
  }
});

test('an elbow injury blocks curls and extensions, which no group-level rule caught', () => {
  assert.ok(blocks(ex('dumbbell biceps curl', 'biceps', 'upper arms'), 'Elbow'));
  assert.ok(blocks(ex('cable triceps pushdown', 'triceps', 'upper arms'), 'Elbow'));
  assert.ok(blocks(ex('ez barbell skull crusher', 'triceps', 'upper arms'), 'Elbow'));
});

test('a wrist injury and a shoulder injury differ, though both are upper_body', () => {
  const curl = ex('dumbbell biceps curl', 'biceps', 'upper arms');
  assert.ok(blocks(curl, 'Wrist'));
  assert.ok(!blocks(curl, 'Shoulder'));

  const raise = ex('dumbbell lateral raise', 'delts', 'shoulders');
  assert.ok(blocks(raise, 'Shoulder'));
  assert.ok(!blocks(raise, 'Wrist'));
});

test('each lower-body region blocks what actually loads it', () => {
  assert.ok(blocks(ex('barbell full squat', 'glutes', 'upper legs'), 'Knee'));
  assert.ok(blocks(ex('barbell full squat', 'glutes', 'upper legs'), 'Hip'));
  assert.ok(blocks(ex('standing calf raise', 'calves', 'lower legs'), 'Calf'));
  assert.ok(blocks(ex('standing calf raise', 'calves', 'lower legs'), 'Ankle'));
  assert.ok(blocks(ex('barbell romanian deadlift', 'hamstrings', 'upper legs'), 'Hamstring'));
  assert.ok(blocks(ex('cable adduction', 'adductors', 'upper legs'), 'Groin'));
  assert.ok(blocks(ex('lever leg extension', 'quads', 'upper legs'), 'Quadriceps'));
  assert.ok(blocks(ex('backward jump', 'quads', 'upper legs'), 'Foot'));
});

test('an upper-back or neck injury blocks pulling and shrugging', () => {
  assert.ok(blocks(ex('barbell bent-over row', 'upper back', 'back'), 'Upper back'));
  assert.ok(blocks(ex('dumbbell shrug', 'traps', 'back'), 'Neck'));
  assert.ok(blocks(ex('dumbbell shrug', 'traps', 'back'), 'Upper back'));
});

test('a hand injury blocks grip-dependent work', () => {
  assert.ok(blocks(ex('dumbbell farmer carry', 'forearms', 'lower arms'), 'Hand'));
  assert.ok(blocks(ex('pull-up', 'lats', 'back'), 'Hand'));
  assert.ok(blocks(ex('barbell deadlift', 'glutes', 'upper legs'), 'Hand'));
});

test('anything targeting the spine or waist is unsafe for the spine regions', () => {
  assert.equal(isSpineSafe(ex('crunch', 'abs', 'waist')), false);
  assert.equal(isSpineSafe(ex('hyperextension', 'spine', 'back')), false);
  assert.equal(isSpineSafe(ex('pull-up', 'lats', 'back')), false);
});

test('supported and isolated limb work is spine-safe', () => {
  assert.equal(isSpineSafe(ex('dumbbell seated biceps curl', 'biceps', 'upper arms')), true);
  assert.equal(isSpineSafe(ex('lever seated calf raise', 'calves', 'lower legs')), true);
  assert.equal(isSpineSafe(ex('dumbbell lying triceps extension', 'triceps', 'upper arms')), true);
});

test('the allow-list does not treat an equipment name as body support', () => {
  // All four are real live rows that an earlier allow-list let through.
  // 'cable pull through' is a loaded hip hinge; its 'band'/'dumbbell' siblings
  // were flagged, and only the 'cable ' prefix spared it.
  assert.equal(isSpineSafe(ex('cable pull through (with rope)', 'glutes', 'upper legs')), false);
  assert.equal(isSpineSafe(ex('lever reverse hyperextension', 'glutes', 'upper legs')), false);
  // Tagged with a limb muscle group, but still a bar-hanging pull-up.
  assert.equal(isSpineSafe(ex('biceps pull-up', 'biceps', 'upper arms')), false);
  assert.equal(isSpineSafe(ex('biceps narrow pull-ups', 'biceps', 'upper arms')), false);
});

test('genuine body-position support is still allowed', () => {
  // The fix must not over-tighten: a seated or lying exercise is still safe,
  // and 'lever seated calf raise' qualifies on 'seated', not on 'lever '.
  assert.equal(isSpineSafe(ex('lever seated calf raise', 'calves', 'lower legs')), true);
  assert.equal(isSpineSafe(ex('dumbbell lying triceps extension', 'triceps', 'upper arms')), true);
  assert.equal(isSpineSafe(ex('dumbbell bench press', 'pectorals', 'chest')), true);
});

test('a spine-safe exercise gets no Lower back or Core row', () => {
  const curl = ex('dumbbell seated biceps curl', 'biceps', 'upper arms');
  assert.ok(!blocks(curl, 'Lower back'));
  assert.ok(!blocks(curl, 'Core'));
});

test('space-separated compounds are caught, not just hyphenated ones', () => {
  // 'archer push up', 'clap push up' and 10 more are live rows. A hyphen-only
  // pattern left every one of them safe-looking for a shoulder or elbow injury.
  for (const name of ['archer push up', 'clap push up', 'deep push up']) {
    const e = ex(name, 'pectorals', 'chest');
    assert.ok(blocks(e, 'Shoulder'), `${name} should block Shoulder`);
    assert.ok(blocks(e, 'Elbow'), `${name} should block Elbow`);
  }
  assert.ok(blocks(ex('archer pull up', 'lats', 'back'), 'Shoulder'));
  assert.ok(blocks(ex('flexion leg sit up (bent knee)', 'abs', 'waist'), 'Neck'));
});

test('the tightened patterns do not fire on look-alike names', () => {
  // 'extension' alone once matched leg and hip extension for Elbow.
  assert.ok(!blocks(ex('lever leg extension', 'quads', 'upper legs'), 'Elbow'));
  assert.ok(!blocks(ex('bench hip extension', 'glutes', 'upper legs'), 'Elbow'));
  // bare 'hop' once matched 'chop'.
  assert.ok(!blocks(ex('cable wood chop', 'abs', 'waist'), 'Calf'));
  // bare 'press' once matched 'leg press' for Wrist.
  assert.ok(!blocks(ex('lever leg press', 'quads', 'upper legs'), 'Wrist'));
});

test('at most one row per region, because uq_ec forbids more', () => {
  const rows = classifyContraindications(ex('barbell overhead squat', 'quads', 'upper legs'));
  const seen = rows.map((r) => r.region);
  assert.equal(new Set(seen).size, seen.length);
});

test('every row names a real seeded region and carries a pattern', () => {
  for (const row of classifyContraindications(ex('barbell full squat', 'glutes', 'upper legs'))) {
    assert.ok(REGIONS.includes(row.region), `${row.region} is not a seeded region`);
    assert.ok(row.pattern.length > 0);
    assert.ok(row.pattern.length <= 32); // the column is VARCHAR(32)
  }
});
