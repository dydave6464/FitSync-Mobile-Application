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
    # Excluding both muscle groups the fixture catalogue can offer leaves nothing
    # selectable. That must be a retryable error, not a 200 with no exercises.
    eq, inj = catalogue["equipment"], catalogue["injuries"]
    response = client.post("/generate-plan", json={
        "mainGoal": "build_muscle",
        "equipment": [{"equipmentId": eq["body weight"], "name": "Bodyweight"}],
        "injuries": [
            {"injuryId": inj["Knee"], "regionGroup": "lower_body"},
            {"injuryId": inj["Lower back"], "regionGroup": "upper_body"},
        ],
    })
    assert response.status_code == 503
    assert "catalogue" in response.json()["detail"].lower()
