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
    "activity",
    ["sedentary", "light", "moderate", "active", "very_active", None],
)
def test_every_plan_is_three_days_a_week(activity):
    # Activity level used to raise this to four or five. One session is
    # generated and repeated, so more days meant the same six exercises more
    # often rather than more training -- and a plan nobody keeps to.
    assert derive(profile(activityLevel=activity)).days_per_week == 3


@pytest.mark.parametrize("level", ["beginner", "intermediate"])
def test_experience_does_not_change_the_days_either(level):
    assert derive(profile(activityLevel="very_active",
                          fitnessLevel=level)).days_per_week == 3


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


def test_no_profile_field_changes_the_default_split():
    # The split is the caller's choice, never inferred from the profile: with
    # no override, every goal and every experience level lands on full body.
    # Migration 013 added day_no and derive can return any of the four styles
    # now, so what this pins is the DEFAULT -- across the whole goal and level
    # matrix, which the single-profile onboarding test below does not cover.
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


def test_no_overrides_is_still_full_body_three_days():
    # The onboarding path. POST /profile/complete-onboarding sends no
    # overrides, and someone's first plan must stay the simplest thing that
    # works -- see the design, section 2.
    params = derive(profile())
    assert params.split_style == "full_body"
    assert params.days_per_week == 3


def test_an_override_chooses_the_split():
    params = derive(profile(), {"splitStyle": "push_pull_legs"}).split_style
    assert params == "push_pull_legs"


def test_days_per_week_is_taken_from_the_override():
    params = derive(profile(), {"daysPerWeek": 5})
    assert params.days_per_week == 5


def test_days_per_week_is_clamped_to_a_real_week():
    assert derive(profile(), {"daysPerWeek": 0}).days_per_week == 1
    assert derive(profile(), {"daysPerWeek": 99}).days_per_week == 7


def test_session_length_override_changes_the_exercise_count():
    # 60 minutes carries two more exercises than 45 -- EXERCISES_BY_SESSION.
    short = derive(profile(), {"sessionLengthMin": 45})
    long = derive(profile(), {"sessionLengthMin": 60})
    assert short.session_length_min == 45 and short.exercise_count == 6
    assert long.session_length_min == 60 and long.exercise_count == 8


def test_an_unknown_session_length_snaps_to_the_nearest_supported_one():
    # EXERCISES_BY_SESSION only knows 45 and 60; a slider that sends 52 must
    # not KeyError the whole request.
    assert derive(profile(), {"sessionLengthMin": 52}).session_length_min == 45
    assert derive(profile(), {"sessionLengthMin": 58}).session_length_min == 60


def test_an_unknown_split_style_falls_back_without_raising():
    # derive reports the RESOLVED slug, so a bad value never reaches the
    # database as a split_style no reader knows.
    assert derive(profile(), {"splitStyle": "sideways"}).split_style == "full_body"


def test_a_beginner_override_is_still_honoured():
    # The beginner session cap shapes the DERIVED length. An explicit choice
    # is the user's, and overriding it silently would make the slider lie.
    params = derive(profile(fitnessLevel="beginner"), {"sessionLengthMin": 60})
    assert params.session_length_min == 60
