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
    candidates = [c(30, "quads"), c(10, "quads"), c(20, "quads")]
    assert select(candidates, 1)[0].exercise_id == 10


def test_generation_is_deterministic():
    candidates = [c(i, MUSCLE_PRIORITY[i % len(MUSCLE_PRIORITY)]) for i in range(40)]
    first = select(candidates, 8)
    for _ in range(5):
        assert select(list(reversed(candidates)), 8) == first


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
