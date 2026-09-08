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

# Arms are reserved rather than ranked.
#
# They sit 8th and 9th in MUSCLE_PRIORITY while a session is six or eight
# exercises, so the priority walk ended before reaching them: triceps appeared
# only in an eight-exercise plan and biceps could not appear at any length. As
# every training day repeats the one session, that is a week with no direct arm
# work in a plan the app calls full body.
ARM_GROUPS: Tuple[str, ...] = ("triceps", "biceps")


def _arm_reservation(count: int) -> int:
    """How many slots to hold back for arms.

    One per three exercises, capped at both: a six-exercise session reserves
    two, and a three-exercise one reserves a single arm rather than handing two
    thirds of the session to isolation work.
    """
    return min(len(ARM_GROUPS), count // 3)


def _rank(muscle_group: str) -> int:
    try:
        return MUSCLE_PRIORITY.index(muscle_group)
    except ValueError:
        # A group the priority list does not name still gets offered; it simply
        # sorts after every named one.
        return _UNLISTED


def select(candidates: Sequence[Candidate], count: int) -> List[Candidate]:
    # The caller's order is the ranker's preference when a model is loaded. With
    # no model, fetch_candidates already returns exercise_id-ascending, so this
    # is exactly the old lowest-id tiebreak and determinism is unchanged.
    order = {c.exercise_id: index for index, c in enumerate(candidates)}

    by_group: Dict[str, List[Candidate]] = {}
    for candidate in candidates:
        by_group.setdefault(candidate.muscle_group, []).append(candidate)
    for group in by_group:
        by_group[group].sort(key=lambda x: (order[x.exercise_id], x.exercise_id))

    # Taken before the priority walk, and only where the catalogue actually
    # offers one -- a user whose equipment rules out every arm exercise gets a
    # full session of what is left, not one two exercises short.
    reserved = [by_group[group][0]
                for group in ARM_GROUPS[:_arm_reservation(count)]
                if by_group.get(group)]
    spoken_for = {x.muscle_group for x in reserved}

    groups = sorted((g for g in by_group if g not in spoken_for),
                    key=lambda g: (_rank(g), g))

    chosen: List[Candidate] = []
    depth = 0
    limit = count - len(reserved)
    # Round-robin: one exercise from each group in priority order, then round
    # again if the count is not met. A group that runs dry is skipped rather
    # than padded from another -- fewer exercises beats a wrong one.
    while len(chosen) < limit:
        added_this_pass = False
        for group in groups:
            if len(chosen) >= limit:
                break
            bucket = by_group[group]
            if depth < len(bucket):
                chosen.append(bucket[depth])
                added_this_pass = True
        if not added_this_pass:
            break
        depth += 1

    # Arms last: compounds while fresh, isolation after. The slot is reserved,
    # not promoted.
    return chosen + reserved
