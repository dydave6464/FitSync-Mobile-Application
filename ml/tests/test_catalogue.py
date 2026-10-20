import pytest

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


def test_a_password_with_url_metacharacters_survives_the_connection_url():
    # Built by hand this would misparse: '@' would look like a host separator.
    from app.config import Settings
    from app.db import create_engine_from

    settings = Settings.from_env({
        "FITSYNC_DB_HOST": "127.0.0.1",
        "FITSYNC_DB_PORT": "3306",
        "FITSYNC_DB_USER": "fitsync",
        "FITSYNC_DB_PASSWORD": "p@ss:w/rd#1%2",
        "FITSYNC_DB_NAME": "fitsync_test",
    })
    engine = create_engine_from(settings)
    assert engine.url.password == "p@ss:w/rd#1%2"
    assert engine.url.host == "127.0.0.1"
    assert engine.url.database == "fitsync_test"


def test_a_stretch_is_not_a_candidate(engine, catalogue):
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert "fixture quad stretch" not in names(result), "a categorised stretch must not be offered"


def test_an_uncategorised_exercise_is_still_a_candidate(engine, catalogue):
    # The COALESCE path. A missing row must degrade to today's behaviour, not
    # remove the exercise -- an unseeded database must not empty the catalogue.
    # `fixture push-up` has no category row and no equipment requirement.
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert "fixture push-up" in names(result)


def test_an_explicit_strength_exercise_is_still_a_candidate(engine, catalogue):
    eq = catalogue["equipment"]
    result = fetch_candidates(engine, [eq["body weight"], eq["dumbbell"]], [], [])
    assert "fixture dumbbell curl" in names(result)


def ordered(candidates):
    """Names in returned order. `names()` sorts, which would hide the ordering."""
    return [c.name for c in candidates]


def test_equipment_the_user_selected_is_offered_before_body_weight(engine, catalogue):
    # Body weight is unioned into `owned` unconditionally so a bench-only user
    # can still finish onboarding (main.py). That makes body-weight exercises
    # eligible for everyone -- and because they cluster at low exercise_ids,
    # ordering by id alone hands a dumbbell owner a plan of push-ups.
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"]]
    result = ordered(fetch_candidates(engine, owned, [], [], [eq["dumbbell"]]))
    assert result[0] == "fixture dumbbell curl"


def test_selecting_nothing_reproduces_the_exercise_id_order(engine, catalogue):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"]]
    assert ordered(fetch_candidates(engine, owned, [], [], [])) == ordered(
        fetch_candidates(engine, owned, [], [])
    )


def test_selecting_a_parent_prefers_its_children(engine, catalogue):
    # 'machines' is the curated onboarding chip; 'cable' is a child of it. The
    # preference must walk the same parent link the eligibility filter does.
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["machines"]]
    result = ordered(fetch_candidates(engine, owned, [], [], [eq["machines"]]))
    assert result[0] == "fixture cable row"


def test_preference_never_changes_which_exercises_are_eligible(engine, catalogue):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"]]
    assert sorted(ordered(fetch_candidates(engine, owned, [], [], [eq["dumbbell"]]))) == sorted(
        ordered(fetch_candidates(engine, owned, [], []))
    )


def test_a_gym_puts_machine_exercises_first(engine, catalogue):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    result = ordered(
        fetch_candidates(engine, owned, [], [], owned, "commercial_gym")
    )
    assert result[0] == "fixture cable row"


def test_a_home_gym_puts_machine_exercises_last(engine, catalogue):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    result = ordered(fetch_candidates(engine, owned, [], [], owned, "home_gym"))
    assert result[-1] == "fixture cable row"


def test_somewhere_else_puts_body_weight_before_dumbbells(engine, catalogue):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"]]
    result = ordered(fetch_candidates(engine, owned, [], [], owned, "other"))
    assert result.index("fixture inverted row") < result.index("fixture dumbbell curl")


@pytest.mark.parametrize("location", ["both", None, "the_moon"])
def test_no_location_preference_keeps_the_existing_order(engine, catalogue, location):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    assert ordered(
        fetch_candidates(engine, owned, [], [], owned, location)
    ) == ordered(fetch_candidates(engine, owned, [], [], owned))


@pytest.mark.parametrize("location", ["commercial_gym", "home_gym", "other"])
def test_location_never_changes_which_exercises_are_eligible(engine, catalogue, location):
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    assert sorted(
        ordered(fetch_candidates(engine, owned, [], [], owned, location))
    ) == sorted(ordered(fetch_candidates(engine, owned, [], [], owned)))


def test_selected_equipment_still_outranks_location(engine, catalogue):
    # A gym-goer who ticked only dumbbells still gets dumbbells first: what
    # they chose beats what their location suggests.
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    result = ordered(
        fetch_candidates(engine, owned, [], [], [eq["dumbbell"]], "commercial_gym")
    )
    assert result[0] == "fixture dumbbell curl"


# The team's curated marks (exercise_preferences). The catalogue fixture marks
# every row 'alternative' and beginner-friendly; each test below re-marks only
# what it is about through the `mark` fixture.
#
# Body weight alone reaches four fixture rows, in exercise_id order:
# push-up, squat, inverted row, glute bridge.


def test_search_only_and_never_are_never_offered(engine, catalogue, mark):
    mark("fixture push-up", "search_only", beginner_friendly=True)
    mark("fixture squat", "never", beginner_friendly=True)
    eq = catalogue["equipment"]
    result = names(fetch_candidates(engine, [eq["body weight"]], [], []))
    assert result == ["fixture glute bridge", "fixture inverted row"]


def test_a_beginner_is_offered_only_beginner_friendly_rows(engine, catalogue, mark):
    mark("fixture push-up", "alternative", beginner_friendly=False)
    mark("fixture squat", None)  # unmarked: nobody has said it suits a beginner
    eq = catalogue["equipment"]
    beginner = fetch_candidates(engine, [eq["body weight"]], [], [], beginner_only=True)
    assert names(beginner) == ["fixture glute bridge", "fixture inverted row"]

    everyone = fetch_candidates(engine, [eq["body weight"]], [], [])
    assert names(everyone) == [
        "fixture glute bridge", "fixture inverted row",
        "fixture push-up", "fixture squat",
    ]


def test_first_then_alternative_then_unmarked(engine, catalogue, mark):
    # Against exercise_id both ways: the highest-id row is the first choice and
    # the lowest-id row is unmarked.
    mark("fixture glute bridge", "first")
    mark("fixture push-up", None)
    eq = catalogue["equipment"]
    result = ordered(fetch_candidates(engine, [eq["body weight"]], [], []))
    assert result == [
        "fixture glute bridge",   # first
        "fixture squat",          # alternative, lower id
        "fixture inverted row",   # alternative
        "fixture push-up",        # unmarked
    ]


def test_a_higher_id_first_beats_a_lower_id_alternative(engine, catalogue, mark):
    mark("fixture inverted row", "first")
    eq = catalogue["equipment"]
    result = ordered(fetch_candidates(engine, [eq["body weight"]], [], []))
    assert result.index("fixture inverted row") < result.index("fixture push-up")


def test_priority_comes_before_the_selected_equipment(engine, catalogue, mark):
    # Push-up and fly are both first choices: inside that priority the
    # dumbbell the user ticked still wins, though push-up has the lower id.
    # The curl is only an alternative, so it follows the body-weight push-up
    # even though its equipment was selected.
    mark("fixture push-up", "first")
    mark("fixture dumbbell fly", "first")
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"]]
    result = ordered(fetch_candidates(engine, owned, [], [], [eq["dumbbell"]]))
    assert result[:2] == ["fixture dumbbell fly", "fixture push-up"]
    assert result[2] == "fixture dumbbell curl"


def test_priority_comes_before_the_location(engine, catalogue, mark):
    # At a gym machines lead -- but only among rows of the same priority.
    mark("fixture push-up", "first")
    eq = catalogue["equipment"]
    owned = [eq["body weight"], eq["dumbbell"], eq["machines"]]
    result = ordered(
        fetch_candidates(engine, owned, [], [], owned, "commercial_gym")
    )
    assert result[:2] == ["fixture push-up", "fixture cable row"]


@pytest.mark.parametrize(
    "kit",
    [
        ("body weight",),
        ("body weight", "dumbbell"),
        ("dumbbell",),
        ("dumbbell", "bench"),
        ("machines",),
        ("body weight", "pull-up bar"),
    ],
)
def test_beginner_only_never_changes_which_equipment_is_eligible(engine, catalogue, kit):
    # Every fixture row is beginner-friendly by default, so any difference
    # here could only come from the equipment filter moving.
    eq = catalogue["equipment"]
    owned = [eq[name] for name in kit]
    assert names(
        fetch_candidates(engine, owned, [], [], beginner_only=True)
    ) == names(fetch_candidates(engine, owned, [], []))
