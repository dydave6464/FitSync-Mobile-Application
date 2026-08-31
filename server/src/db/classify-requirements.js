'use strict';

// The upstream dataset gives each exercise exactly one equipment tag, so it can
// say "this is a dumbbell exercise" but not "this needs a dumbbell AND a
// bench". Bench and pull-up bar are prerequisites layered on top of a primary
// implement, not sources of exercises. See the design, section 5.
//
// Returns curated equipment names (equipment.name as seeded by
// seed-equipment.js), not raw upstream tags.

const FREE_WEIGHT = new Set([
  'dumbbell', 'barbell', 'ez barbell', 'olympic barbell', 'trap bar',
  'band', 'resistance band', 'kettlebell',
]);

// A machine station carries its own pad or seat, and is already gated behind
// the 'machines' onboarding option. Requiring a user-owned bench on top would
// lock a gym-goer out of equipment they demonstrably have.
const MACHINE = new Set(['cable', 'leverage machine', 'smith machine']);

// The catalogue writes these compounds three ways -- 'pull-up', 'pull up' and
// 'pullup' -- so the separator is optional AND may be a space. A hyphen-only
// pattern misses the live rows 'archer pull up' and 'pull up (neutral grip)'.
// SAYS_BENCH matches the plural too: 'triceps dip (between benches)' is live.
const SAYS_BENCH = /\bbenche?s?\b/;
const IMPLIES_BENCH = /\b(incline|decline|lying|prone|supine)\b/;
// Bar-dependent is wider than the words "pull-up": a muscle-up, a front lever,
// a hanging leg raise and skin-the-cat all need a bar and none say "pull-up".
const SAYS_BAR = /\b(pull[\s-]?ups?|chin[\s-]?ups?)\b|\bhanging\b|muscle[\s-]?up|front lever|back lever|skin the cat|arm slingers|on straight bar|\bring dips\b/;
// 'lying'/'incline' does not mean a bench when the name says otherwise.
const NOT_A_BENCH = /\bfloor\b|exercise ball|stability ball|bosu/;

// Names the patterns above get wrong. Each value is the final answer for that
// exercise, returned verbatim -- not a hint the patterns then refine.
const OVERRIDES = new Map([
  ['bench dip on floor', []],
  ['bench pull-ups', ['bench']],
  ['inverse leg curl (on pull-up cable machine)', ['machines']],
  ['chest dip (on dip-pull-up cage)', ['machines']],
]);

function classifyRequirements(exercise) {
  const name = String(exercise.name || '').toLowerCase();
  if (OVERRIDES.has(name)) return [...OVERRIDES.get(name)];

  const equipment = String(exercise.equipment || '').toLowerCase();
  if (MACHINE.has(equipment)) return [];

  if (equipment === 'body weight') {
    if (SAYS_BAR.test(name)) return ['pull-up bar'];
    if (SAYS_BENCH.test(name) && !NOT_A_BENCH.test(name)) return ['bench'];
    return [];
  }

  if (FREE_WEIGHT.has(equipment) && !NOT_A_BENCH.test(name)
      && (SAYS_BENCH.test(name) || IMPLIES_BENCH.test(name))) {
    return ['bench'];
  }

  return [];
}

module.exports = { classifyRequirements, OVERRIDES, FREE_WEIGHT, MACHINE };
