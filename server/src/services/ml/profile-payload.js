'use strict';

/// What leaves Node for the Python ML service, built from an allowed list.
///
/// The service needs a user's goal, level, activity, equipment and injuries to
/// build a plan, and a few check-in answers to estimate risk. It has no use for
/// who they are. So each request is built field by field from what the
/// service reads, rather than by deleting known personal fields from the
/// profile: a field added to the profile later stays in Node unless someone
/// adds it here on purpose. Email, name, user id, city, date of birth, sex,
/// height, weight, goal weight, training location and the account flags are
/// never sent -- no rule reads any of them (ML service design, section 9.1).

function toEquipmentRef(e) {
  return { equipmentId: e.equipmentId, name: e.name };
}

function toInjuryRef(i) {
  return {
    injuryId: i.injuryId,
    name: i.name,
    isLateral: i.isLateral,
    regionGroup: i.regionGroup,
    side: i.side,
  };
}

/// The body of POST /generate-plan. [profile] is getProfile's shape, with the
/// generator screen's `overrides` when it sent any.
function toPlanPayload(profile) {
  const payload = {
    mainGoal: profile.mainGoal ?? null,
    fitnessLevel: profile.fitnessLevel ?? null,
    activityLevel: profile.activityLevel ?? null,
    equipment: (profile.equipment ?? []).map(toEquipmentRef),
    injuries: (profile.injuries ?? []).map(toInjuryRef),
  };
  if (profile.overrides) payload.overrides = profile.overrides;
  return payload;
}

/// The body of POST /injury-risk: each check-in's date and four answers, the
/// training-load index, and injury history in the same shape as a plan's.
function toRiskPayload({ checkins = [], load = 0, injuryHistory = [] }) {
  return {
    checkins: checkins.map((c) => ({
      checkinDate: c.checkinDate,
      sleepQuality: c.sleepQuality,
      muscleSoreness: c.muscleSoreness,
      energy: c.energy,
      stress: c.stress,
    })),
    load,
    injuryHistory: injuryHistory.map(toInjuryRef),
  };
}

module.exports = { toPlanPayload, toRiskPayload };
