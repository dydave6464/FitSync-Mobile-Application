'use strict';
const { PAIN_LEVELS } = require('../../db/session-outcomes');

/// What leaves Node for the Python ML service, built from an allowed list.
///
/// Each request carries only the fields the service's rules actually read,
/// built field by field rather than by deleting known personal fields from
/// the profile, so a field added to the profile later stays in Node unless
/// someone adds it here on purpose (ML service design, section 9.1).
///
/// Read today, and so sent: the goal, fitness level and training location;
/// equipment and injury ids; each injury's body region (it excludes muscle
/// groups); every chosen goal (to name the plan); the generator screen's split,
/// days per week and session length; whether a stored health check asks for a
/// gentler plan (healthCaution); and each check-in's four answers with the
/// training-load index; for the risk estimate, the reported injuries and the
/// worst recent pain level. Never sent: email, name, user id, city, date of birth,
/// sex, height, weight, goal weight, activity level, account flags, catalogue
/// names, injury side, the health check's conditions and answers, and
/// check-in ids and dates -- no rule reads any of them.

function list(value) {
  return Array.isArray(value) ? value : [];
}

function toInjuryRef(i) {
  return { injuryId: i.injuryId, regionGroup: i.regionGroup };
}

/// The generator screen's three choices, and nothing else that might ride
/// along in the object.
function toOverrides(o) {
  const out = {};
  for (const key of ['splitStyle', 'daysPerWeek', 'sessionLengthMin']) {
    if (o[key] !== undefined) out[key] = o[key];
  }
  return out;
}

/// The body of POST /generate-plan. [profile] is getProfile's shape, with the
/// generator screen's `overrides` when it sent any.
function toPlanPayload(profile) {
  const p = profile ?? {};
  const payload = {
    mainGoal: p.mainGoal ?? null,
    fitnessLevel: p.fitnessLevel ?? null,
    trainingLocation: p.trainingLocation ?? null,
    healthCaution: p.healthCaution === true,
    equipment: list(p.equipment).map((e) => ({ equipmentId: e.equipmentId })),
    injuries: list(p.injuries).map(toInjuryRef),
    goals: list(p.goals),
  };
  if (p.overrides && typeof p.overrides === 'object') {
    payload.overrides = toOverrides(p.overrides);
  }
  return payload;
}

/// The body of POST /injury-risk: each check-in's four answers, the
/// training-load index, injury history in the same shape as a plan's, and the
/// worst pain level reported over recent sessions.
///
/// recentPain is left out, not sent as null, when there were no reports: the
/// service reads both as "no reports", and a body without the key is the one
/// an ML service from before the field existed already accepts. An unknown
/// spelling is dropped the same way rather than forwarded, since the
/// service's rules would score it as no pain at all without saying so.
function toRiskPayload(request) {
  const r = request ?? {};
  const payload = {
    checkins: list(r.checkins).map((c) => ({
      sleepQuality: c.sleepQuality,
      muscleSoreness: c.muscleSoreness,
      energy: c.energy,
      stress: c.stress,
    })),
    load: r.load ?? 0,
    injuryHistory: list(r.injuryHistory).map(toInjuryRef),
  };
  if (PAIN_LEVELS.includes(r.recentPain)) payload.recentPain = r.recentPain;
  return payload;
}

module.exports = { toPlanPayload, toRiskPayload };
