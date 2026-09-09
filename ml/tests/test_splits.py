import pytest

from app.rules.splits import SPLITS, resolve


def test_full_body_is_one_day_over_every_group():
    slug, split = resolve("full_body")
    assert slug == "full_body"
    assert split.rotation == 1
    assert split.days[0].name == "Full body"
    # Empty means "no filter" rather than "no muscles" -- full body is the
    # behaviour that existed before splits and must keep the whole catalogue.
    assert split.days[0].muscle_groups == ()


def test_push_pull_legs_is_three_named_days():
    _, split = resolve("push_pull_legs")
    assert split.rotation == 3
    assert [d.name for d in split.days] == ["Push", "Pull", "Legs"]


def test_push_day_is_push_muscles():
    _, split = resolve("push_pull_legs")
    assert split.days[0].muscle_groups == ("pectorals", "delts", "triceps")


def test_upper_lower_is_two_days_and_upper_is_push_plus_pull():
    _, split = resolve("upper_lower")
    assert split.rotation == 2
    assert [d.name for d in split.days] == ["Upper", "Lower"]
    _, ppl = resolve("push_pull_legs")
    push, pull, legs = (set(d.muscle_groups) for d in ppl.days)
    assert set(split.days[0].muscle_groups) == push | pull
    assert set(split.days[1].muscle_groups) == legs


def test_cardio_core_is_one_day():
    _, split = resolve("cardio_core")
    assert split.rotation == 1
    assert split.days[0].name == "Cardio & core"
    assert split.days[0].muscle_groups == ("cardiovascular system", "abs")


@pytest.mark.parametrize("value", [None, "", "sideways", "PUSH_PULL_LEGS"])
def test_anything_unrecognised_falls_back_to_full_body(value):
    # Permissive on purpose, like the rest of ProfileRequest: rejecting a
    # split style blocks a user from getting a plan at all.
    slug, split = resolve(value)
    assert slug == "full_body"
    assert split.rotation == 1


def test_every_split_has_exactly_rotation_days():
    for slug, split in SPLITS.items():
        assert len(split.days) == split.rotation, slug


def test_days_within_a_rotation_do_not_share_muscles():
    # Disjoint pools are what make cross-day de-duplication unnecessary: a
    # Push day and a Pull day cannot pick the same exercise.
    for slug, split in SPLITS.items():
        seen = set()
        for day in split.days:
            assert not (seen & set(day.muscle_groups)), f"{slug}: {day.name} repeats a group"
            seen |= set(day.muscle_groups)
