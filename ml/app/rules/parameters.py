"""Profile -> the shape of a plan. Pure: no database, no config, no clock.

Nothing collects days per week or session length from the user -- those columns
exist only on workout_plans, never on users -- so the service derives them.
See the design, sections 6.1 to 6.3.
"""
from typing import Any, Mapping, NamedTuple

# Three days for everyone, whatever their activity level says.
#
# It used to scale to four or five. That reads as a reward for being active and
# is not one: a single session is generated and repeated, so a fifth day is the
# same six exercises a fifth time, not more training. Three is also the
# schedule a beginner keeps to, and the one full-body programmes are written
# around -- a day between sessions for the muscle worked to recover.
#
# Activity level still shapes the calorie estimate the About step shows; it no
# longer shapes the plan.
DAYS_PER_WEEK = 3

LONG_SESSION_GOALS = ("gain_strength", "build_muscle")
LONG_SESSION_MIN = 60
SHORT_SESSION_MIN = 45
BEGINNER_SESSION_CAP = 45

# goal -> (sets, reps)
VOLUME = {
    "gain_strength": (4, "4-6"),
    "build_muscle": (4, "8-12"),
    "lose_weight": (3, "12-15"),
    "general_fitness": (3, "10-12"),
}
DEFAULT_VOLUME = VOLUME["general_fitness"]
MIN_SETS = 2

# A 60-minute session carries two more exercises than a 45-minute one.
EXERCISES_BY_SESSION = {LONG_SESSION_MIN: 8, SHORT_SESSION_MIN: 6}


class PlanParameters(NamedTuple):
    split_style: str
    days_per_week: int
    session_length_min: int
    target_sets: int
    target_reps: str
    exercise_count: int


def derive(profile: Mapping[str, Any]) -> PlanParameters:
    is_beginner = profile.get("fitnessLevel") == "beginner"

    goal = profile.get("mainGoal")
    session = LONG_SESSION_MIN if goal in LONG_SESSION_GOALS else SHORT_SESSION_MIN
    if is_beginner:
        session = min(session, BEGINNER_SESSION_CAP)

    sets, reps = VOLUME.get(goal, DEFAULT_VOLUME)
    if is_beginner:
        sets = max(sets - 1, MIN_SETS)

    return PlanParameters(
        # Always full_body: plan_exercises has no day_no, so a plan is one flat
        # ordered list and any other value would be a label its own rows
        # contradict. The choice is revisited when that column exists.
        split_style="full_body",
        days_per_week=DAYS_PER_WEEK,
        session_length_min=session,
        target_sets=sets,
        target_reps=reps,
        exercise_count=EXERCISES_BY_SESSION[session],
    )
