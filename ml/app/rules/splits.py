"""Split style -> a rotation of named days, each over a pool of muscles.

Pure: no database, no config, no clock. The counts in the table below were
measured against the seeded catalogue; the smallest pool, cardio & core, has
198 exercises, which is ample for an eight-exercise session.

A day's pool is a FILTER, not a prescription. selection.select still does the
choosing, with its own priority order and arm reservation -- this only decides
what it is allowed to choose from. See the design, section 4.
"""
from typing import Dict, NamedTuple, Optional, Tuple


class SplitDay(NamedTuple):
    name: str
    # Empty means no filter at all: every group is eligible. That is full
    # body, and it is the behaviour that existed before splits.
    muscle_groups: Tuple[str, ...]


class Split(NamedTuple):
    # How many distinct days before the plan repeats. NOT days_per_week --
    # they are different numbers and conflating them is the easy mistake
    # here. A four-day push_pull_legs week is Push, Pull, Legs, Push: four
    # sessions drawn from a rotation of three.
    rotation: int
    days: Tuple[SplitDay, ...]


_PUSH = ("pectorals", "delts", "triceps")
_PULL = ("lats", "upper back", "biceps", "traps")
_LEGS = ("quads", "glutes", "hamstrings", "calves", "adductors", "abductors")

FULL_BODY = "full_body"

SPLITS: Dict[str, Split] = {
    FULL_BODY: Split(1, (SplitDay("Full body", ()),)),
    "push_pull_legs": Split(3, (
        SplitDay("Push", _PUSH),
        SplitDay("Pull", _PULL),
        SplitDay("Legs", _LEGS),
    )),
    "upper_lower": Split(2, (
        SplitDay("Upper", _PUSH + _PULL),
        SplitDay("Lower", _LEGS),
    )),
    "cardio_core": Split(1, (
        SplitDay("Cardio & core", ("cardiovascular system", "abs")),
    )),
}


def _titled(name: str) -> str:
    """Capitalise each word, leaving the words themselves alone.

    Not str.title(), which also lowercases the rest of every word and
    mangles anything with an apostrophe in it. Only the casing of the first
    letter is this function's business -- the wording belongs to the day.
    """
    return " ".join(word[:1].upper() + word[1:] for word in name.split(" "))


def label(split: Split) -> str:
    """What a plan built from this split is called, before the goal suffix.

    Derived from the day names rather than a second table keyed on split
    style: the days are already the vocabulary, and a parallel table is one
    more thing that can fall out of step with them -- a "Full Body" plan
    whose only day is called "Push" is exactly the contradiction this
    replaces.

    Day names are stored sentence-cased ("Full body") because that is how
    they read as an eyebrow above an exercise list. A plan NAME is a title,
    so it is title-cased here -- which is also what keeps `full_body`
    reading exactly as the "Full Body" every existing plan is named.
    """
    return " / ".join(_titled(day.name) for day in split.days)


def resolve(split_style: Optional[str]) -> Tuple[str, Split]:
    """The split to build, and the slug that was actually used.

    Unrecognised input falls back to full body rather than raising: this model
    is permissive for the same reason ProfileRequest is -- a rejected request
    leaves a user with no plan, which is worse than a simpler plan.
    """
    if split_style in SPLITS:
        return split_style, SPLITS[split_style]
    return FULL_BODY, SPLITS[FULL_BODY]
