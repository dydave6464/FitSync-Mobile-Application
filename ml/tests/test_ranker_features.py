import math

from app import ranker_features as rf

BASE = {
    "mainGoal": "build_muscle", "fitnessLevel": "intermediate",
    "trainingLocation": "home_gym", "sessionLengthMin": 60,
    "splitStyle": "push_pull_legs", "healthCaution": False,
    "mark": "first", "beginnerFriendly": True, "pickedEquipment": True,
    "equipmentName": "dumbbell", "daysSinceTrained": 3,
    "timesDone": 2, "timesSkipped": 1, "timesSwapped": 0,
}


def row(**changes):
    return dict(zip(rf.FEATURES, rf.encode(dict(BASE, **changes))))


def test_features_are_in_the_agreed_order():
    assert rf.FEATURES == (
        "goal_gain_strength", "goal_build_muscle", "goal_lose_weight",
        "goal_improve_endurance", "level", "loc_commercial_gym", "loc_home_gym",
        "loc_other", "session_length_min", "split_push_pull_legs",
        "split_upper_lower", "split_cardio_core", "health_caution", "mark",
        "beginner_friendly", "picked_equipment", "location_fit",
        "days_since_trained", "times_done", "times_skipped", "times_swapped",
    )


def test_monotonic_directions():
    cst = dict(zip(rf.FEATURES, rf.monotonic_cst()))
    assert cst["picked_equipment"] == 1
    assert cst["location_fit"] == 1
    assert cst["days_since_trained"] == 1
    assert cst["times_done"] == 1
    assert cst["times_skipped"] == -1
    assert cst["times_swapped"] == -1
    assert all(v == 0 for k, v in cst.items() if k not in rf.MONOTONIC)


def test_a_full_situation_encodes_every_column():
    r = row()
    assert r["goal_build_muscle"] == 1 and r["goal_gain_strength"] == 0
    assert r["level"] == 2
    assert r["loc_home_gym"] == 1 and r["loc_commercial_gym"] == 0
    assert r["session_length_min"] == 60
    assert r["split_push_pull_legs"] == 1
    assert r["health_caution"] == 0
    assert r["mark"] == 0 and r["beginner_friendly"] == 1
    assert r["picked_equipment"] == 1
    assert r["location_fit"] == 1          # dumbbell is first at a home gym
    assert r["days_since_trained"] == 3
    assert (r["times_done"], r["times_skipped"], r["times_swapped"]) == (2, 1, 0)


def test_general_fitness_full_body_and_no_location_are_all_zero_columns():
    r = row(mainGoal="general_fitness", splitStyle="full_body", trainingLocation="both")
    assert all(r[c] == 0 for c in rf.FEATURES if c.startswith(("goal_", "split_", "loc_")))
    assert r["location_fit"] == 0


def test_missing_or_unknown_values_read_as_the_neutral_one():
    r = dict(zip(rf.FEATURES, rf.encode({})))
    assert r["level"] == 1                  # a skipped level plans as a beginner
    assert r["mark"] == 2                   # unmarked
    assert r["days_since_trained"] == 14    # never trained
    assert r["times_done"] == r["times_skipped"] == r["times_swapped"] == 0
    assert r["session_length_min"] == 45
    assert all(math.isfinite(v) for v in r.values())


def test_values_are_capped_and_garbage_is_neutral():
    r = row(daysSinceTrained=40, timesDone=9, timesSkipped=-3, timesSwapped="x")
    assert r["days_since_trained"] == 14
    assert r["times_done"] == 5
    assert r["times_skipped"] == 0
    assert r["times_swapped"] == 0


def test_location_fit_follows_the_catalogue_tiers():
    assert rf.location_fit("machines", "commercial_gym") == 1
    assert rf.location_fit("dumbbell", "commercial_gym") == 0
    assert rf.location_fit("body weight", "other") == 1
    assert rf.location_fit("dumbbell", "both") == 0
    assert rf.location_fit(None, "home_gym") == 0
