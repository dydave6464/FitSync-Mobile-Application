from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def client_for(tmp_path):
    settings = Settings(db_host="127.0.0.1", db_port=3306, db_user="u",
                        db_password="p", db_name="fitsync_test",
                        model_dir=str(tmp_path))
    return TestClient(create_app(settings))


def post(client, **profile):
    response = client.post("/plan-parameters", json=profile)
    assert response.status_code == 200, response.text
    return response.json()


def test_a_long_goal_intermediate_gets_sixty_minutes_and_eight_exercises(tmp_path):
    body = post(client_for(tmp_path), mainGoal="build_muscle", fitnessLevel="intermediate")
    assert body == {"sessionLengthMin": 60, "exercisesPerDay": 8, "lengthReason": "goal"}


def test_a_beginner_is_capped_and_told_why(tmp_path):
    body = post(client_for(tmp_path), mainGoal="build_muscle", fitnessLevel="beginner")
    assert body == {"sessionLengthMin": 45, "exercisesPerDay": 6, "lengthReason": "level"}


def test_a_health_caution_says_health(tmp_path):
    body = post(client_for(tmp_path), mainGoal="gain_strength",
                fitnessLevel="intermediate", healthCaution=True)
    assert body == {"sessionLengthMin": 45, "exercisesPerDay": 6, "lengthReason": "health"}


def test_a_chosen_length_is_snapped_and_reported_as_chosen(tmp_path):
    client = client_for(tmp_path)
    assert post(client, mainGoal="lose_weight", overrides={"sessionLengthMin": 60}) == {
        "sessionLengthMin": 60, "exercisesPerDay": 8, "lengthReason": "chosen"}
    assert post(client, mainGoal="lose_weight", overrides={"sessionLengthMin": 50})["sessionLengthMin"] == 45


def test_a_bare_profile_answers_like_derive(tmp_path):
    assert post(client_for(tmp_path)) == {
        "sessionLengthMin": 45, "exercisesPerDay": 6, "lengthReason": "goal"}


def test_a_malformed_body_is_a_422_like_generate_plan(tmp_path):
    response = client_for(tmp_path).post("/plan-parameters", json={"equipment": "nope"})
    assert response.status_code == 422
