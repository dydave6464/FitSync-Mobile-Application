'use strict';

// The catalogue says what an exercise trains, not what kind of movement it is.
// This assigns that kind. See the design, section 4.
//
// THE RULE THAT SHAPES THIS FILE: an exercise is 'strength' unless a narrow,
// high-precision rule says otherwise. The two failure modes are not symmetric.
// A stretch wrongly left in a plan is visible and fixable. A strength exercise
// wrongly demoted disappears from every plan permanently and silently.
//
// Rules measured against the live catalogue and REJECTED, because each removes
// real strength exercises (counts are live rows):
//
//   %lever%    74  -- 'lever ' is the plate-loaded MACHINE prefix (71 rows:
//                     'lever alternate leg press'). Only back/front lever are holds.
//   run        35  -- matches 'crunch'
//   rotation    9  -- 'cable standing shoulder external rotation' is strength
//   balance     2  -- 'dumbbell step up single leg balance with bicep curl'
//   hang        4  -- 'kettlebell hang clean'
//   kick        4  -- 'outside leg kick push-up'
//   foam roll / mobility / warm-up / breathing / jump rope
//              0  -- these families do not exist in this catalogue
//
// %lever% and run together would have removed 106 legitimate exercises.
// tests/classify-categories.test.js guards every one of these.

// Order matters: first match wins. 'circles knee stretch' is a stretch, not
// mobility, because the stretch rule is listed first.
const RULES = [
  { category: 'stretch',  pattern: /\bstretch/ },
  { category: 'stretch',  pattern: /\byoga\b|\bpose\b/ },
  { category: 'mobility', pattern: /\bcircles\b/ },
  { category: 'mobility', pattern: /toe touch/ },
  { category: 'other',    pattern: /^(back|front) lever\b/ },
  { category: 'other',    pattern: /^balance board$/ },
  { category: 'other',    pattern: /\bboxing\b/ },
];

function classifyCategory(exercise) {
  const name = String(exercise.name || '').toLowerCase().trim();
  for (const rule of RULES) {
    if (rule.pattern.test(name)) return rule.category;
  }
  return 'strength';
}

module.exports = { classifyCategory, RULES };
