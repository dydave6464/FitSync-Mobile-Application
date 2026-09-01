import pytest

from app.rules.parameters import PlanParameters, derive


def profile(**overrides):
    base = {
        "mainGoal": "build_muscle",
        "fitnessLevel": "intermediate",
        "activityLevel": "moderate",
    }
    base.update(overrides)
    return base


@pytest.mark.parametrize(
    "activity,expected",
    [
        ("sedentary", 3),
        ("light", 3),
        ("moderate", 4),
        ("active", 5),
        ("very_active", 5),
        (None, 3),
    ],
)
def test_days_per_week_follows_activity_level(activity, expected):
    assert derive(profile(activityLevel=activity)).days_per_week == expected


def test_a_beginner_is_capped_at_four_days():
    assert derive(profile(activityLevel="very_active",
                          fitnessLevel="beginner")).days_per_week == 4
    # and is not raised to the cap when their activity implies fewer
    assert derive(profile(activityLevel="sedentary",
                          fitnessLevel="beginner")).days_per_week == 3


@pytest.mark.parametrize(
    "goal,expected",
    [
        ("gain_strength", 60),
        ("build_muscle", 60),
        ("lose_weight", 45),
        ("general_fitness", 45),
    ],
)
def test_session_length_follows_the_goal(goal, expected):
    assert derive(profile(mainGoal=goal)).session_length_min == expected


def test_a_beginners_first_session_is_capped_at_forty_five_minutes():
    params = derive(profile(mainGoal="build_muscle", fitnessLevel="beginner"))
    assert params.session_length_min == 45


@pytest.mark.parametrize(
    "goal,sets,reps",
    [
        ("gain_strength", 4, "4-6"),
        ("build_muscle", 4, "8-12"),
        ("lose_weight", 3, "12-15"),
        ("general_fitness", 3, "10-12"),
    ],
)
def test_volume_follows_the_goal(goal, sets, reps):
    params = derive(profile(mainGoal=goal))
    assert params.target_sets == sets
    assert params.target_reps == reps


def test_a_beginner_loses_one_set_but_keeps_the_rep_range():
    params = derive(profile(mainGoal="gain_strength", fitnessLevel="beginner"))
    assert params.target_sets == 3
    assert params.target_reps == "4-6"


def test_sets_never_fall_below_two():
    params = derive(profile(mainGoal="lose_weight", fitnessLevel="beginner"))
    assert params.target_sets == 2


def test_split_style_is_always_full_body_in_this_phase():
    # plan_exercises has no day_no, so a plan is one flat ordered list. Any
    # other split value would be a label the rows contradict -- spec section 7.
    for goal in ("gain_strength", "build_muscle", "lose_weight", "general_fitness"):
        for level in ("beginner", "intermediate"):
            params = derive(profile(mainGoal=goal, fitnessLevel=level))
            assert params.split_style == "full_body"


def test_exercise_count_follows_session_length():
    assert derive(profile(mainGoal="build_muscle")).exercise_count == 8
    assert derive(profile(mainGoal="lose_weight")).exercise_count == 6


def test_an_empty_profile_yields_safe_defaults_rather_than_raising():
    # A user can reach onboarding completion with nothing filled in --
    # profile_nudge.dart documents that state as supported.
    params = derive({})
    assert params.split_style == "full_body"
    assert 1 <= params.days_per_week <= 7
    assert params.session_length_min > 0
    assert params.target_sets >= 2
    assert params.target_reps
    assert params.exercise_count >= 1


def test_an_unknown_goal_falls_back_rather_than_raising():
    params = derive(profile(mainGoal="become_a_bird"))
    assert params.target_reps == "10-12"


def test_parameters_are_immutable():
    params = derive(profile())
    with pytest.raises(Exception):
        params.days_per_week = 7
    assert isinstance(params, PlanParameters)
