from app.catalogue import fetch_candidates


def names(candidates):
    return sorted(c.name for c in candidates)


def test_only_owned_equipment_is_offered(engine, catalogue):
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert "fixture push-up" in names(result)
    assert "fixture dumbbell curl" not in names(result)


def test_owning_a_parent_reaches_its_children(engine, catalogue):
    # user_equipment holds curated rows ('machines'); exercises point at raw
    # tags ('cable'). Ownership must walk parent_equipment_id or every machine
    # exercise is invisible to everyone.
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["machines"]], [], [])
    assert "fixture cable row" in names(result)


def test_a_requirement_the_user_does_not_own_removes_the_exercise(engine, catalogue):
    eq = catalogue["equipment"]
    without_bar = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert "fixture pull-up" not in names(without_bar)

    with_bar = fetch_candidates(
        engine, [eq["body weight"], eq["pull-up bar"]], [], []
    )
    assert "fixture pull-up" in names(with_bar)


def test_a_bench_exercise_needs_both_the_dumbbell_and_the_bench(engine, catalogue):
    eq = catalogue["equipment"]
    dumbbells_only = fetch_candidates(engine, [eq["dumbbell"]], [], [])
    assert "fixture dumbbell bench press" not in names(dumbbells_only)

    both = fetch_candidates(engine, [eq["dumbbell"], eq["bench"]], [], [])
    assert "fixture dumbbell bench press" in names(both)


def test_a_contraindicated_exercise_is_excluded_for_that_injury(engine, catalogue):
    eq, inj = catalogue["equipment"], catalogue["injuries"]
    healthy = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert "fixture squat" in names(healthy)

    injured = fetch_candidates(engine, [eq["body weight"]], [inj["Knee"]], [])
    assert "fixture squat" not in names(injured)


def test_an_unrelated_injury_does_not_exclude_it(engine, catalogue):
    eq, inj = catalogue["equipment"], catalogue["injuries"]
    result = fetch_candidates(engine, [eq["body weight"]], [inj["Lower back"]], [])
    assert "fixture squat" in names(result)


def test_target_muscle_groups_are_excluded(engine, catalogue):
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"]], [], ["pectorals"])
    assert "fixture push-up" not in names(result)


def test_no_equipment_yields_nothing_rather_than_everything(engine, catalogue):
    # The failure direction matters: an empty owned list must not degrade into
    # "no filter". The caller substitutes body weight; the query does not guess.
    assert fetch_candidates(engine, [], [], []) == []


def test_results_are_ordered_by_exercise_id_for_determinism(engine, catalogue):
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"], eq["dumbbell"]], [], [])
    ids = [c.exercise_id for c in result]
    assert ids == sorted(ids)
