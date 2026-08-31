'use strict';

// muscle_group records the muscle a movement TRAINS, not the structure it
// LOADS. 'barbell deadlift' is tagged 'glutes'. Filtering injuries on muscle
// group alone misses 18 of 19 deadlifts and 69 of 72 squats in the live
// catalogue. See the design, section 6.5.
//
// Keyed on the specific injury region, not its region_group. A wrist injury and
// a shoulder injury are both 'upper_body' but rule out different exercises, and
// an elbow injury matches no group-level pattern at all.

// The 16 regions seed-injuries.js creates. Kept in one place so the seed can
// assert every name it emits resolves to a row.
const REGIONS = [
  'Shoulder', 'Elbow', 'Wrist', 'Hand',
  'Neck', 'Upper back', 'Lower back', 'Core',
  'Hip', 'Groin', 'Hamstring', 'Quadriceps', 'Knee', 'Calf', 'Ankle', 'Foot',
];

// The two spine regions use the allow-list below rather than a deny pattern.
const SPINE_REGIONS = ['Lower back', 'Core'];

// Deny patterns for the fourteen regions whose risky-movement set converges.
// Several are deliberately narrower than they first look:
//   - Elbow uses /\bcurl/ and an explicit 'triceps', not a bare 'extension',
//     which would have caught 'leg extension' and 'hip extension'.
//   - Calf/Ankle/Foot use /\bhops?\b/, not a bare 'hop', which caught 'chop'.
//   - Wrist uses a lookbehind so 'leg press' is not a wrist load.
//   - Every compound separator is [\s-]? , never -? : the catalogue carries
//     'archer push up', 'clap push up' and 10 more space-separated push-up
//     variants. A hyphen-only pattern left all of them uncontraindicated for
//     a shoulder or elbow injury, which is a safety gap, not a cosmetic one.
const DENY = [
  { region: 'Shoulder', pattern: 'shoulder_load',
    re: /overhead|military|bench press|chest press|\bdips?\b|push[\s-]?ups?|\bfly\b|flye|lateral raise|front raise|upright row|behind.?the.?neck|behind neck|snatch|jerk|pull[\s-]?ups?|chin[\s-]?ups?|shoulder press|arnold|handstand/ },
  { region: 'Elbow', pattern: 'elbow_load',
    re: /\bcurl|triceps|tricep|skull|close.?grip|\bdips?\b|push[\s-]?ups?|chin[\s-]?ups?|pull[\s-]?ups?|pushdown|kickback|elbow/ },
  { region: 'Wrist', pattern: 'wrist_load',
    re: /push[\s-]?ups?|plank|front squat|clean|snatch|\bcurl|wrist|farmer|carry|\bhang|pull[\s-]?ups?|chin[\s-]?ups?|\brow\b|(?<!leg )press/ },
  { region: 'Hand', pattern: 'grip_load',
    re: /grip|farmer|carry|\bhang|deadlift|pull[\s-]?ups?|chin[\s-]?ups?|\brow\b|\bcurl|shrug/ },
  { region: 'Neck', pattern: 'neck_load',
    re: /shrug|overhead|military|behind.?the.?neck|behind neck|bridge|sit[\s-]?ups?|crunch|inverted|neck/ },
  { region: 'Upper back', pattern: 'upper_back_load',
    re: /\brow\b|pull[\s-]?ups?|chin[\s-]?ups?|shrug|deadlift|overhead|pulldown|pullover|face pull/ },
  { region: 'Hip', pattern: 'hip_load',
    re: /squat|lunge|deadlift|hip thrust|hip raise|abduction|adduction|leg raise|step[\s-]?up|good morning|swing|bridge/ },
  { region: 'Groin', pattern: 'adductor_load',
    re: /adduction|adductor|sumo|wide stance|lateral lunge|side lunge|cossack|split squat|straddle/ },
  { region: 'Hamstring', pattern: 'hamstring_load',
    re: /deadlift|leg curl|good morning|sprint|lunge|swing|romanian|stiff leg|hyperextension|glute.?ham/ },
  { region: 'Quadriceps', pattern: 'quad_load',
    re: /squat|lunge|leg extension|step[\s-]?up|jump|leg press|sissy|pistol/ },
  { region: 'Knee', pattern: 'knee_load',
    re: /squat|lunge|leg extension|jump|step[\s-]?up|pistol|sissy|leg press|sprint|skater/ },
  { region: 'Calf', pattern: 'calf_load',
    re: /calf|jump|sprint|\bskips?\b|\brun|\bhops?\b|toe raise|plantar/ },
  { region: 'Ankle', pattern: 'ankle_load',
    re: /calf|jump|sprint|lunge|step[\s-]?up|\bskips?\b|\brun|\bhops?\b|ankle|balance/ },
  { region: 'Foot', pattern: 'foot_load',
    re: /jump|sprint|\brun|calf|step[\s-]?up|\bhops?\b|\bskips?\b|toe|plantar/ },
];

// Lower back and Core invert to an allow-list. Their deny-list does not
// converge: after a first pass a second found 187 more back-risky exercises,
// and every added pattern costs precision. Default-deny is the honest answer
// for the two regions where nearly every compound movement is a risk.
const SPINE_TARGET = new Set([
  'spine', 'abs', 'upper back', 'traps', 'levator scapulae', 'lats',
]);
const LIMB_ISOLATION = new Set([
  'biceps', 'triceps', 'forearms', 'calves', 'delts', 'pectorals',
]);
// SUPPORTED lists BODY POSITIONS only. It deliberately contains no equipment
// name: an earlier draft included 'cable ' and 'lever ', which let
// 'cable pull through (with rope)' -- a loaded hip hinge, mechanically a
// Romanian deadlift -- return zero contraindication rows, while its own
// siblings 'band pull through' and 'dumbbell sumo pull through' were correctly
// flagged. Naming the load source is not evidence the spine is supported. That
// is the same category error as trusting muscle_group, recurring inside the
// allow-list built to avoid it.
const SUPPORTED = /seated|lying|supine|prone|on bench|bench |floor|wall|preacher|kneeling/;
const SPINE_RISK = /deadlift|good morning|bent.?over|clean|snatch|jerk|squat|lunge|overhead|over.?head|above head|military|push press|standing.*press|carry|walk|swing|twist|side bend|hanging|\brow\b|thruster|farmer|pull[\s-]?ups?|chin[\s-]?ups?|pull through|hyperextension|hip thrust|romanian|stiff leg/;

function isSpineSafe(exercise) {
  const name = String(exercise.name || '').toLowerCase();
  // Lowercased for the same reason `name` is: the failure direction of a casing
  // mismatch here is spine-SAFE, which is the wrong way to be wrong.
  const muscleGroup = String(exercise.muscle_group || '').toLowerCase();
  const bodyPart = String(exercise.body_part || '').toLowerCase();
  if (SPINE_TARGET.has(muscleGroup)) return false;
  if (bodyPart === 'back' || bodyPart === 'waist') return false;
  if (SPINE_RISK.test(name)) return false;
  return SUPPORTED.test(name) || LIMB_ISOLATION.has(muscleGroup);
}

function classifyContraindications(exercise) {
  const name = String(exercise.name || '').toLowerCase();
  const rows = [];

  if (!isSpineSafe(exercise)) {
    for (const region of SPINE_REGIONS) rows.push({ region, pattern: 'not_spine_safe' });
  }
  for (const rule of DENY) {
    if (rule.re.test(name)) rows.push({ region: rule.region, pattern: rule.pattern });
  }

  // uq_ec is (exercise_id, injury_id), so a region may appear once. Keep the
  // first pattern matched: iteration order is fixed, so the stored reason stays
  // stable across seed runs rather than flipping between equivalent causes.
  const seen = new Set();
  return rows.filter((row) => {
    if (seen.has(row.region)) return false;
    seen.add(row.region);
    return true;
  });
}

module.exports = {
  classifyContraindications, isSpineSafe, REGIONS, SPINE_REGIONS, DENY,
};
