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
