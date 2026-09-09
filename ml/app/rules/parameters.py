"""Profile -> the shape of a plan. Pure: no database, no config, no clock.

Nothing collects days per week or session length from the user -- those columns
exist only on workout_plans, never on users -- so the service derives them.
See the design, sections 6.1 to 6.3.
"""
from typing import Any, Mapping, NamedTuple, Optional

from app.rules.splits import resolve as resolve_split

# Three days by default, whatever the activity level says.
#
# It used to scale to four or five. That reads as a reward for being active and
# is not one: this is the default, and the default plan is full body -- a
# rotation of one day -- so a fifth day is that same session a fifth time, not
# more training. Three is also the schedule a beginner keeps to, and the one
# full-body programmes are written around: a day between sessions for the
# muscle worked to recover.
#
# A split with a longer rotation does have distinct days to spread across,
# which is why days per week is an override rather than a constant now. Nothing
# sends one during onboarding, so a first plan still lands here.
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

MIN_DAYS_PER_WEEK = 1
MAX_DAYS_PER_WEEK = 7


class PlanParameters(NamedTuple):
    split_style: str
    days_per_week: int
    session_length_min: int
    target_sets: int
    target_reps: str
    exercise_count: int


def _nearest_session_length(requested: int) -> int:
    """Snap to a length EXERCISES_BY_SESSION actually knows.

    The generator's slider is continuous and this table has two entries, so an
    unsnapped value would KeyError the whole request. Ties go to the shorter
    session: a plan someone finishes beats one they abandon.
    """
    return min(EXERCISES_BY_SESSION, key=lambda known: (abs(known - requested), known))


def derive(profile: Mapping[str, Any],
           overrides: Optional[Mapping[str, Any]] = None) -> PlanParameters:
    overrides = overrides or {}
    is_beginner = profile.get("fitnessLevel") == "beginner"

    goal = profile.get("mainGoal")
    session = LONG_SESSION_MIN if goal in LONG_SESSION_GOALS else SHORT_SESSION_MIN
    if is_beginner:
        session = min(session, BEGINNER_SESSION_CAP)

    # An explicit choice wins over the derived one, beginner cap included: the
    # cap shapes a default, and silently overriding a value the user moved a
    # slider to would make the slider a lie.
    requested_length = overrides.get("sessionLengthMin")
    if requested_length is not None:
        session = _nearest_session_length(int(requested_length))

    sets, reps = VOLUME.get(goal, DEFAULT_VOLUME)
    if is_beginner:
        sets = max(sets - 1, MIN_SETS)

    # Resolved, not passed through: an unrecognised value becomes full_body
    # here, so nothing downstream stores a split_style it cannot read back.
    split_style, _ = resolve_split(overrides.get("splitStyle"))

    days = overrides.get("daysPerWeek")
    days = DAYS_PER_WEEK if days is None else int(days)
    days = max(MIN_DAYS_PER_WEEK, min(MAX_DAYS_PER_WEEK, days))

    return PlanParameters(
        split_style=split_style,
        days_per_week=days,
        session_length_min=session,
        target_sets=sets,
        target_reps=reps,
        exercise_count=EXERCISES_BY_SESSION[session],
    )
