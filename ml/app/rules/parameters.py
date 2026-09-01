"""Profile -> the shape of a plan. Pure: no database, no config, no clock.

Nothing collects days per week or session length from the user -- those columns
exist only on workout_plans, never on users -- so the service derives them.
See the design, sections 6.1 to 6.3.
"""
from typing import Any, Mapping, NamedTuple

DAYS_BY_ACTIVITY = {
    "sedentary": 3,
    "light": 3,
    "moderate": 4,
    "active": 5,
    "very_active": 5,
}
DEFAULT_DAYS = 3
BEGINNER_DAY_CAP = 4

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

    days = DAYS_BY_ACTIVITY.get(profile.get("activityLevel"), DEFAULT_DAYS)
    if is_beginner:
        days = min(days, BEGINNER_DAY_CAP)

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
        days_per_week=days,
        session_length_min=session,
        target_sets=sets,
        target_reps=reps,
        exercise_count=EXERCISES_BY_SESSION[session],
    )
