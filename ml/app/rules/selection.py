"""Candidates -> an ordered session. Pure: no database, no randomness.

Determinism is a requirement, not an accident: the same profile and the same
catalogue must yield the same plan, so the thesis can reproduce a result and a
test can assert one. Ties break on the lowest exercise_id, matching the
tiebreaker resolveExerciseIds already uses on the Node side.

The cost is that every user with identical inputs gets an identical plan. That
is correct here and dull in a product; varying it is a model concern, deferred.
See the design, sections 6.6 and 13.
"""
from typing import Dict, List, Sequence, Tuple

from app.catalogue import Candidate

# Largest muscle first, so a short session still covers the big movements.
MUSCLE_PRIORITY: Tuple[str, ...] = (
    "quads",
    "pectorals",
    "lats",
    "hamstrings",
    "glutes",
    "delts",
    "upper back",
    "triceps",
    "biceps",
    "abs",
    "calves",
    "forearms",
    "traps",
    "adductors",
    "abductors",
    "spine",
)

_UNLISTED = len(MUSCLE_PRIORITY)


def _rank(muscle_group: str) -> int:
    try:
        return MUSCLE_PRIORITY.index(muscle_group)
    except ValueError:
        # A group the priority list does not name still gets offered; it simply
        # sorts after every named one.
        return _UNLISTED


def select(candidates: Sequence[Candidate], count: int) -> List[Candidate]:
    by_group: Dict[str, List[Candidate]] = {}
    for candidate in candidates:
        by_group.setdefault(candidate.muscle_group, []).append(candidate)
    for group in by_group:
        by_group[group].sort(key=lambda x: x.exercise_id)

    groups = sorted(by_group, key=lambda g: (_rank(g), g))

    chosen: List[Candidate] = []
    depth = 0
    # Round-robin: one exercise from each group in priority order, then round
    # again if the count is not met. A group that runs dry is skipped rather
    # than padded from another -- fewer exercises beats a wrong one.
    while len(chosen) < count:
        added_this_pass = False
        for group in groups:
            if len(chosen) >= count:
                break
            bucket = by_group[group]
            if depth < len(bucket):
                chosen.append(bucket[depth])
                added_this_pass = True
        if not added_this_pass:
            break
        depth += 1

    return chosen
