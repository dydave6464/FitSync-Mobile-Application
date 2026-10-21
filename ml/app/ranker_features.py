"""How one (trainee, exercise, history) situation becomes plan-ranker inputs.

One encoder, used three ways, so a feature means the same thing in training
and in use: the simulation builds its rows in this column order
(app/ranker_data.py), the training CLI encodes real CSV rows with it
(app/train_ranker.py --real), and the service encodes each candidate at plan
time (app/ranker.py).

Every value a request or a CSV can get wrong reads as the neutral one rather
than raising: a feature must never fail a user's plan.
"""
import math
from typing import Any, List, Mapping, Optional

from app.catalogue import LOCATION_FIRST

# One-hot columns. The goal, location and split each have one value with no
# column of its own (general_fitness; both/unanswered; full_body): all zeros.
GOALS = ("gain_strength", "build_muscle", "lose_weight", "improve_endurance")
LOCATIONS = ("commercial_gym", "home_gym", "other")
SPLITS = ("push_pull_legs", "upper_lower", "cardio_core")
# A skipped or unknown level plans as a beginner (rules/parameters.py).
LEVELS = {"new": 0, "beginner": 1, "intermediate": 2}
DEFAULT_LEVEL = 1
MARKS = {"first": 0, "alternative": 1, "unmarked": 2}
DEFAULT_MARK = 2
DEFAULT_SESSION_MIN = 45

DAYS_CAP = 14
COUNT_CAP = 5

FEATURES = (
    "goal_gain_strength", "goal_build_muscle", "goal_lose_weight",
    "goal_improve_endurance",
    "level",
    "loc_commercial_gym", "loc_home_gym", "loc_other",
    "session_length_min",
    "split_push_pull_legs", "split_upper_lower", "split_cardio_core",
    "health_caution",
    "mark", "beginner_friendly",
    "picked_equipment", "location_fit",
    "days_since_trained", "times_done", "times_skipped", "times_swapped",
)

# +1: a higher value can never lower the predicted chance; -1: never raise it.
# A skip or a swap can therefore never move an exercise up.
MONOTONIC = {
    "picked_equipment": 1,
    "location_fit": 1,
    "days_since_trained": 1,
    "times_done": 1,
    "times_skipped": -1,
    "times_swapped": -1,
}


def monotonic_cst() -> List[int]:
    return [MONOTONIC.get(name, 0) for name in FEATURES]


def location_fit(equipment_name: Optional[str], training_location: Optional[str]) -> int:
    """1 when the catalogue's location tier puts this equipment first here.

    The same table catalogue._LOCATION_TIER orders by, so the model sees the
    rule the candidates were sorted with.
    """
    first = LOCATION_FIRST.get(training_location or "")
    return int(bool(first) and equipment_name in first)


def _number(value: Any, low: float, high: float, default: float) -> float:
    if isinstance(value, bool):
        value = int(value)
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(number):
        return default
    return min(max(number, low), high)


def _flag(value: Any) -> float:
    return 1.0 if value is True or value == 1 or value == "1" else 0.0


def encode(situation: Mapping[str, Any]) -> List[float]:
    """One row in FEATURES order.

    Keys: mainGoal, fitnessLevel, trainingLocation, sessionLengthMin,
    splitStyle, healthCaution, mark, beginnerFriendly, pickedEquipment,
    equipmentName, daysSinceTrained (None = never trained), timesDone,
    timesSkipped, timesSwapped. Missing or unusable values read as neutral.
    """
    s = situation
    goal = s.get("mainGoal")
    location = s.get("trainingLocation")
    split = s.get("splitStyle")
    days = s.get("daysSinceTrained")
    row = [1.0 if goal == g else 0.0 for g in GOALS]
    row.append(float(LEVELS.get(s.get("fitnessLevel"), DEFAULT_LEVEL)))
    row.extend(1.0 if location == loc else 0.0 for loc in LOCATIONS)
    row.append(_number(s.get("sessionLengthMin"), 0, 240, DEFAULT_SESSION_MIN))
    row.extend(1.0 if split == sp else 0.0 for sp in SPLITS)
    row.append(_flag(s.get("healthCaution")))
    row.append(float(MARKS.get(s.get("mark"), DEFAULT_MARK)))
    row.append(_flag(s.get("beginnerFriendly")))
    row.append(_flag(s.get("pickedEquipment")))
    row.append(float(location_fit(s.get("equipmentName"), location)))
    row.append(DAYS_CAP if days is None else _number(days, 0, DAYS_CAP, DAYS_CAP))
    row.append(_number(s.get("timesDone"), 0, COUNT_CAP, 0))
    row.append(_number(s.get("timesSkipped"), 0, COUNT_CAP, 0))
    row.append(_number(s.get("timesSwapped"), 0, COUNT_CAP, 0))
    return row
