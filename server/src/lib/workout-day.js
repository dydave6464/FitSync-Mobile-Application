'use strict';

/// Whether a day is a workout day: an active plan, and the day's weekday is
/// one of the chosen training days (every day when none are chosen).
///
/// The one copy of the rule. Daily Routine's workout item and the Schedule's
/// planned days both ask it, so the two never disagree about a day.
function isPlannedWorkoutDay({ hasActivePlan, trainingDays, weekday }) {
  if (!hasActivePlan) return false;
  return trainingDays.length === 0 || trainingDays.includes(weekday);
}

module.exports = { isPlannedWorkoutDay };
