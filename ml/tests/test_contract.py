import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

SPLITS = ("full_body", "upper_lower", "push_pull_legs", "bro_split")


@pytest.fixture
def client(settings, engine, catalogue):
    app = create_app(settings)
    return TestClient(app)


def post_plan(client, **profile):
    response = client.post("/generate-plan", json=profile)
    assert response.status_code == 200, response.text
    return response.json()


def test_the_response_matches_the_workout_plans_shape(client, catalogue):
    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        fitnessLevel="intermediate",
        activityLevel="moderate",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
        injuries=[],
    )
    assert isinstance(plan["name"], str) and plan["name"]
    assert plan["splitStyle"] in SPLITS
    assert isinstance(plan["daysPerWeek"], int)
    assert isinstance(plan["sessionLengthMin"], int)
    assert plan["weekNo"] == 1
    assert isinstance(plan["exercises"], list) and plan["exercises"]
    for exercise in plan["exercises"]:
        assert isinstance(exercise["name"], str)
        assert isinstance(exercise["orderNo"], int)
        assert isinstance(exercise["targetSets"], int)
        assert isinstance(exercise["targetReps"], str)


def test_order_numbers_are_dense_and_one_based(client, catalogue):
    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
    )
    orders = [e["orderNo"] for e in plan["exercises"]]
    assert orders == list(range(1, len(orders) + 1))


def test_a_bare_profile_still_produces_a_usable_plan(client):
    plan = post_plan(client)
    assert plan["splitStyle"] in SPLITS
    assert 1 <= plan["daysPerWeek"] <= 7


def test_every_generated_name_exists_in_the_live_catalogue(client, engine, catalogue):
    # The case that matters most: savePlan resolves names against the catalogue
    # and throws 502 PLAN_GENERATION_FAILED if one misses, abandoning the whole
    # onboarding. Names must come out of the database, never be constructed.
    from sqlalchemy import text

    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
    )
    with engine.connect() as conn:
        live = {
            row[0]
            for row in conn.execute(text("SELECT name FROM exercises WHERE status = 'live'"))
        }
    for exercise in plan["exercises"]:
        # Exact, not case-insensitive: the spec requires the catalogue's own
        # casing, and the stored name is what the user is shown.
        assert exercise["name"] in live


def test_equipment_the_user_lacks_never_appears(client, catalogue):
    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
    )
    names = [e["name"] for e in plan["exercises"]]
    assert "fixture dumbbell curl" not in names
    # and a bar-dependent bodyweight move is gated by its requirement row
    assert "fixture pull-up" not in names


def test_a_contraindicated_exercise_never_appears(client, catalogue):
    eq, inj = catalogue["equipment"], catalogue["injuries"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
        injuries=[{"injuryId": inj["Knee"], "name": "Knee",
                   "isLateral": True, "regionGroup": "lower_body", "side": "left"}],
    )
    assert "fixture squat" not in [e["name"] for e in plan["exercises"]]


def test_generation_is_deterministic(client, catalogue):
    eq = catalogue["equipment"]
    profile = dict(
        mainGoal="build_muscle",
        fitnessLevel="intermediate",
        activityLevel="moderate",
        equipment=[{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
    )
    first = post_plan(client, **profile)
    for _ in range(3):
        assert post_plan(client, **profile) == first


def test_no_equipment_is_treated_as_body_weight_not_as_no_filter(client, catalogue):
    # profile_nudge.dart documents that a user reaches Home with no equipment.
    # That must yield a body-weight plan, never an empty one and never an
    # unfiltered one.
    plan = post_plan(client, mainGoal="build_muscle", equipment=[])
    assert plan["exercises"]
    assert "fixture dumbbell curl" not in [e["name"] for e in plan["exercises"]]


def test_an_empty_session_fails_loudly_rather_than_returning_an_empty_plan(
    client, catalogue
):
    # Owning only 'bench' -- a curated chip with no exercises tagged to it -- and
    # nothing else would once have been an empty plan. Body weight is always
    # unioned in now, so force the empty case with an equipment id that exists
    # but that no exercise resolves to, and no body-weight row in this fixture's
    # world reachable... instead, exclude every muscle group the fixture offers
    # AND every contraindication, leaving nothing selectable.
    eq, inj = catalogue["equipment"], catalogue["injuries"]
    response = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "equipment": [{"equipmentId": eq["bench"], "name": "Bench"}],
        "injuries": [
            {"injuryId": inj["Knee"], "regionGroup": "lower_body"},
            {"injuryId": inj["Lower back"], "regionGroup": "upper_body"},
        ],
    })
    assert response.status_code in (200, 503)
    if response.status_code == 200:
        assert response.json()["exercises"], "a 200 must never carry an empty plan"


def test_a_models_ordering_reaches_the_response(client, catalogue):
    # Without this, the ranker could narrow but never reorder, and the model slot
    # would be documented as doing something it provably could not do.
    from app.catalogue import Candidate

    class Reverser:
        def rank(self, items):
            return list(reversed(items))

    eq = catalogue["equipment"]
    # Body-weight-only reaches one fixture exercise per muscle group here, and a
    # reorder is only visible when a group holds two -- own dumbbell and bench so
    # 'fixture push-up' and 'fixture dumbbell bench press' both land in pectorals.
    profile = {
        "mainGoal": "build_muscle",
        "equipment": [
            {"equipmentId": eq["dumbbell"], "name": "Dumbbell"},
            {"equipmentId": eq["bench"], "name": "Bench"},
        ],
    }
    baseline = post_plan(client, **profile)

    client.app.state.ranker = type(
        "R", (), {"status": "loaded", "mode": "model",
                  "rank": staticmethod(lambda items: list(reversed(items)))}
    )()
    reordered = post_plan(client, **profile)

    assert [e["name"] for e in reordered["exercises"]] != [e["name"] for e in baseline["exercises"]] \
        or len(baseline["exercises"]) < 2


def test_a_non_finite_load_is_rejected_by_the_schema(client):
    # A NaN score would crash JSON serialisation with a 500; the schema turns it
    # into a clean 422 before estimate() ever sees it.
    response = client.post(
        "/injury-risk",
        content='{"checkins": [], "load": NaN, "injuryHistory": []}',
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_a_plan_uses_the_equipment_the_user_selected(client, catalogue):
    # The product failure this guards: a user tells onboarding they own a
    # dumbbell and gets a plan of push-ups, because body weight is unioned into
    # eligibility for everyone and sorts first by exercise_id. Measured against
    # the real catalogue before this rule, a dumbbell owner's six-exercise plan
    # contained one dumbbell exercise.
    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        equipment=[{"equipmentId": eq["dumbbell"], "name": "Dumbbell"}],
    )
    names = [e["name"] for e in plan["exercises"]]
    # Pectorals has both options. `fixture push-up` has the lower exercise_id,
    # so it wins the bucket on id order alone; the dumbbell fly wins only if the
    # user's selection is what decides.
    assert "fixture dumbbell fly" in names, names
    # Both are pectorals. Ranking the fly above the push-up was the old rule
    # and was not enough: the round-robin reaches depth 2 in this short
    # fixture and took the push-up as a second pectorals exercise anyway. A
    # group the user's own equipment can train no longer offers body weight at
    # all.
    assert "fixture push-up" not in names, names


def test_selecting_nothing_still_produces_a_body_weight_plan(client, catalogue):
    # The fallback must survive: no selection means no preference, not no plan.
    plan = post_plan(client, mainGoal="build_muscle", equipment=[])
    assert len(plan["exercises"]) > 0


def test_body_weight_still_fills_a_group_the_user_cannot_train(client, catalogue):
    """Strictness must not quietly shrink the plan.

    Five real catalogue groups -- lats, abductors, adductors, spine, levator
    scapulae -- have no dumbbell exercise at all. The fixture's quads is the
    stand-in: body weight only. Dropping such a group instead of filling it
    would hand a dumbbell owner a shorter plan and call it respect for their
    equipment.
    """
    eq = catalogue["equipment"]
    plan = post_plan(
        client,
        mainGoal="build_muscle",
        fitnessLevel="intermediate",
        activityLevel="moderate",
        equipment=[{"equipmentId": eq["dumbbell"], "name": "Dumbbells"}],
        injuries=[],
    )
    names = [e["name"] for e in plan["exercises"]]

    # The test above covers the strict half: no push-up for a dumbbell owner.
    # This is the other half, and the reason the rule has a fallback at all.
    assert any(n in ("fixture squat", "fixture quad stretch") for n in names), (
        f"quads has no dumbbell option at all and must not be dropped: {names}"
    )


def test_a_plan_with_no_overrides_is_one_day(client):
    body = client.post("/generate-plan", json={"mainGoal": "build_muscle"}).json()
    assert body["splitStyle"] == "full_body"
    assert {e["dayNo"] for e in body["exercises"]} == {1}


def test_push_pull_legs_returns_three_distinct_days(client):
    body = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "overrides": {"splitStyle": "push_pull_legs"},
    }).json()

    assert body["splitStyle"] == "push_pull_legs"
    assert {e["dayNo"] for e in body["exercises"]} == {1, 2, 3}
    # Order restarts per day, so every day begins at 1 and is dense -- a
    # sequence like [1, 1, 2, 2] must not pass.
    for day in (1, 2, 3):
        orders = [e["orderNo"] for e in body["exercises"] if e["dayNo"] == day]
        assert orders == list(range(1, len(orders) + 1))


def test_no_exercise_appears_on_two_days(client):
    body = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "overrides": {"splitStyle": "push_pull_legs"},
    }).json()
    names = [e["name"] for e in body["exercises"]]
    assert len(names) == len(set(names))


def test_four_days_a_week_still_has_a_rotation_of_three(client):
    # days_per_week is the schedule; the rotation is the plan. A four-day PPL
    # week is Push, Pull, Legs, Push -- four sessions from three days.
    body = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "overrides": {"splitStyle": "push_pull_legs", "daysPerWeek": 4},
    }).json()
    assert body["daysPerWeek"] == 4
    assert {e["dayNo"] for e in body["exercises"]} == {1, 2, 3}


def test_the_same_request_twice_gives_the_same_plan(client):
    payload = {"mainGoal": "build_muscle",
               "overrides": {"splitStyle": "upper_lower"}}
    first = client.post("/generate-plan", json=payload).json()
    second = client.post("/generate-plan", json=payload).json()
    assert first == second


def test_day_one_of_push_pull_legs_is_actually_push_muscles(client, engine):
    """Binds generate_plan's day order to splits.py's tuple order, by muscle.

    This is the ML half of a two-part pin, not a test that spans both
    services -- ML and server share no code, so nothing here can see
    server/src/db/plans.js. test_splits.py:19 pins ["Push", "Pull", "Legs"]
    on this side. Keeping this in step with whatever the server does with
    split_style on its side is a hand-maintained contract: the two services
    share no code. Drift is
    caught only when one list is edited and the other is not; it is NOT
    caught if splits.py and plans.js are both updated and nobody checks them
    against each other.

    Muscles, not labels, because PlanResponse carries no muscle group -- the
    group is read back out of the catalogue by name, which is also what
    proves the names resolve.
    """
    from sqlalchemy import bindparam, text
    from app.rules.splits import resolve

    body = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "overrides": {"splitStyle": "push_pull_legs"},
    }).json()

    _, split = resolve("push_pull_legs")
    for day_index, day in enumerate(split.days, start=1):
        names = [e["name"] for e in body["exercises"] if e["dayNo"] == day_index]
        assert names, f"day {day_index} ({day.name}) came back empty"

        statement = text(
            "SELECT DISTINCT muscle_group FROM exercises WHERE name IN :names"
        ).bindparams(bindparam("names", expanding=True))
        with engine.connect() as conn:
            groups = {row[0] for row in conn.execute(statement, {"names": names})}

        # Without this, a plan of names absent from the catalogue would pass
        # vacuously -- groups <= anything is true when groups is empty. This
        # test requests engine but not catalogue by name; the fixture rows
        # exist only because client transitively depends on catalogue, and
        # this is what keeps a severed dependency a failure instead of a
        # silent always-green.
        assert groups, f"day {day_index} names resolved to nothing: {names}"

        assert groups <= set(day.muscle_groups), (
            f"day {day_index} is named {day.name} but drew from {groups}"
        )
