from app.catalogue import Candidate
from app.rules.selection import MUSCLE_PRIORITY, select


def c(exercise_id, muscle_group, name=None):
    return Candidate(exercise_id, name or "ex{}".format(exercise_id), muscle_group)


def test_one_exercise_per_muscle_group_in_priority_order():
    candidates = [
        c(10, "biceps"), c(11, "quads"), c(12, "pectorals"), c(13, "lats"),
    ]
    chosen = select(candidates, 4)
    assert [x.muscle_group for x in chosen] == ["quads", "pectorals", "lats", "biceps"]


def test_ties_break_on_the_lowest_exercise_id():
    # select() now honours the caller's order (see
    # test_the_callers_order_is_honoured_so_a_ranker_can_reorder below), so this
    # only holds for input already in ascending id order -- exactly what
    # fetch_candidates hands select() when no model is loaded.
    candidates = [c(10, "quads"), c(20, "quads"), c(30, "quads")]
    assert select(candidates, 1)[0].exercise_id == 10


def test_generation_is_deterministic():
    # select() is now order-sensitive by design (a model's ranking must reach
    # the response), so determinism means "the same input yields the same
    # output every time", not "input order does not matter".
    candidates = [c(i, MUSCLE_PRIORITY[i % len(MUSCLE_PRIORITY)]) for i in range(40)]
    first = select(candidates, 8)
    for _ in range(5):
        assert select(candidates, 8) == first


def test_a_muscle_group_with_no_candidates_is_skipped_not_padded():
    candidates = [c(10, "quads"), c(11, "biceps")]
    chosen = select(candidates, 8)
    assert len(chosen) == 2
    assert [x.muscle_group for x in chosen] == ["quads", "biceps"]


def test_it_never_returns_more_than_asked():
    candidates = [c(i, MUSCLE_PRIORITY[i % len(MUSCLE_PRIORITY)]) for i in range(40)]
    assert len(select(candidates, 6)) == 6


def test_a_second_pass_fills_the_count_when_groups_run_out():
    # Two groups, six slots: after one exercise each, it comes back around
    # rather than returning a two-exercise session.
    candidates = [c(10, "quads"), c(11, "quads"), c(12, "quads"),
                  c(20, "pectorals"), c(21, "pectorals"), c(22, "pectorals")]
    chosen = select(candidates, 6)
    assert len(chosen) == 6
    assert len({x.exercise_id for x in chosen}) == 6


def test_no_exercise_is_ever_repeated():
    candidates = [c(10, "quads"), c(20, "pectorals")]
    chosen = select(candidates, 8)
    assert len({x.exercise_id for x in chosen}) == len(chosen)


def test_an_empty_candidate_list_yields_an_empty_session():
    assert select([], 8) == []


def test_a_muscle_group_outside_the_priority_list_is_still_usable():
    # The catalogue has 19 muscle groups; the priority list names fewer. An
    # unlisted group must not vanish -- it sorts last, but it is offered.
    chosen = select([c(10, "serratus anterior")], 8)
    assert len(chosen) == 1


def test_the_callers_order_is_honoured_so_a_ranker_can_reorder():
    # Spec section 8's payoff is that a model can down-rank a movement class for
    # one user. That only works if select() respects the order it is handed.
    ranked = [c(30, "quads"), c(10, "quads"), c(20, "quads")]
    assert select(ranked, 1)[0].exercise_id == 30
    # and with the natural (id-ascending) order, the lowest id still wins
    assert select([c(10, "quads"), c(20, "quads"), c(30, "quads")], 1)[0].exercise_id == 10


def _one_per_group():
    """A candidate in every named group, ids ascending in priority order."""
    return [c(100 + i, g) for i, g in enumerate(MUSCLE_PRIORITY)]


def test_every_plan_reserves_an_arm_slot():
    # Arms sit 8th and 9th in MUSCLE_PRIORITY, and a session is 6 or 8
    # exercises, so the list was cut off before reaching them: biceps could
    # not appear in any plan at any session length, and triceps only in an
    # 8-exercise one. A full-body plan with no direct arm work all week is not
    # what "full body" means to anyone reading it.
    groups = [x.muscle_group for x in select(_one_per_group(), 6)]

    assert "biceps" in groups, groups
    assert "triceps" in groups, groups


def test_the_arms_come_last_in_the_session():
    groups = [x.muscle_group for x in select(_one_per_group(), 6)]

    # Compounds first while fresh, isolation after: the arm slots are reserved,
    # not promoted.
    assert groups[-2:] == ["triceps", "biceps"], groups


def test_the_big_movements_still_lead():
    groups = [x.muscle_group for x in select(_one_per_group(), 6)]

    assert groups[:4] == ["quads", "pectorals", "lats", "hamstrings"], groups


def test_no_arm_candidates_means_no_reserved_slots_wasted():
    # A dumbbell-free user, or any catalogue filter that leaves no arm
    # exercise: the session must still be full rather than two short.
    candidates = [x for x in _one_per_group()
                  if x.muscle_group not in ("biceps", "triceps")]

    chosen = select(candidates, 6)

    assert len(chosen) == 6
    assert not {"biceps", "triceps"} & {x.muscle_group for x in chosen}


def test_a_short_session_is_not_swamped_by_arms():
    # Reserving two of three slots for arms would be a worse plan than the one
    # it replaced. Scale the reservation with the session.
    groups = [x.muscle_group for x in select(_one_per_group(), 3)]

    assert groups.count("biceps") + groups.count("triceps") <= 1, groups
    assert groups[0] == "quads", groups


def test_arms_are_not_duplicated_when_the_count_runs_deep():
    # With a second pass available, the reserved arm must not also be taken by
    # the round-robin.
    candidates = _one_per_group() + [c(500, "biceps"), c(501, "triceps")]

    chosen = select(candidates, 10)

    ids = [x.exercise_id for x in chosen]
    assert len(ids) == len(set(ids)), ids

