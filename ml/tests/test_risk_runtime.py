"""The injury-risk model at runtime: loading, falling back, /health and the endpoint.

None of this needs MySQL: /injury-risk and /health read no table, so the app is
built with placeholder credentials and a model directory of the test's own.
"""
import joblib
import pytest
from fastapi.testclient import TestClient

from app import risk_model
from app.config import Settings
from app.main import create_app

CONTRACT_KEYS = {"riskLevel", "trainingLoadScore", "source", "modelVersion",
                 "loadPct", "drivers"}
DRIVER_KEYS = {"load", "sleep", "soreness", "energy", "stress",
               "injury_history", "recent_pain"}


def settings_for(model_dir):
    return Settings(db_host="127.0.0.1", db_port=3306, db_user="u",
                    db_password="p", db_name="fitsync_test",
                    model_dir=str(model_dir))


def client_for(model_dir):
    return TestClient(create_app(settings_for(model_dir)))


def model_file(model_dir):
    return model_dir / risk_model.MODEL_FILENAME


# --- loading ----------------------------------------------------------------


def test_a_missing_model_file_is_trained_in_process(tmp_path):
    loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "trained"
    assert loaded.usable
    assert loaded.version == risk_model.MODEL_VERSION
    # Kept in memory only: the service never writes into its model directory
    # on its own. The training CLI is what produces the file.
    assert not model_file(tmp_path).exists()


def test_a_saved_model_file_is_loaded(tmp_path):
    risk_model.save(risk_model.default_classifier(), str(model_file(tmp_path)))
    loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "loaded"
    assert loaded.usable
    assert loaded.version == risk_model.MODEL_VERSION


def test_a_corrupt_model_file_falls_back_to_rules(tmp_path):
    model_file(tmp_path).write_bytes(b"not a joblib file")
    loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "absent"
    assert not loaded.usable
    assert loaded.version is None


def test_a_file_with_the_wrong_features_falls_back_to_rules(tmp_path):
    # A model trained on other columns would read every request wrongly
    # without ever raising; refusing it is the only safe reading.
    bundle = risk_model.bundle(risk_model.default_classifier())
    bundle["features"] = ["load_pct", "sleep"]
    joblib.dump(bundle, str(model_file(tmp_path)))
    assert risk_model.RiskModel.load(settings_for(tmp_path)).status == "absent"


def test_a_bare_classifier_without_the_bundle_falls_back_to_rules(tmp_path):
    joblib.dump(risk_model.default_classifier(), str(model_file(tmp_path)))
    assert risk_model.RiskModel.load(settings_for(tmp_path)).status == "absent"


def test_a_failure_while_training_in_process_falls_back_to_rules(tmp_path, monkeypatch):
    def broken():
        raise RuntimeError("no scikit-learn here")

    monkeypatch.setattr(risk_model, "default_classifier", broken)
    loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "absent"
    assert not loaded.usable


def stale_bundle(model_dir, sklearn_version):
    """A sound model file that records another scikit-learn (None: none at all)."""
    bundle = risk_model.bundle(risk_model.default_classifier())
    if sklearn_version is None:
        del bundle["sklearnVersion"]
    else:
        bundle["sklearnVersion"] = sklearn_version
    joblib.dump(bundle, str(model_file(model_dir)))
    return model_file(model_dir).read_bytes()


def test_a_file_from_another_scikit_learn_is_retrained_in_process(tmp_path, caplog):
    # A forest pickled by another scikit-learn may unpickle without error and
    # still predict wrongly, so the file is not used: the service trains the
    # default model from the seeded simulation instead, and says why.
    import sklearn

    before = stale_bundle(tmp_path, "0.24.2")
    with caplog.at_level("WARNING", logger="app.risk_model"):
        loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "trained"
    assert loaded.usable
    assert loaded.version == risk_model.MODEL_VERSION
    assert "0.24.2" in caplog.text and sklearn.__version__ in caplog.text
    # The stale file is left exactly as it was, for whoever put it there.
    assert model_file(tmp_path).read_bytes() == before


def test_a_file_that_records_no_scikit_learn_version_is_retrained(tmp_path, caplog):
    stale_bundle(tmp_path, None)
    with caplog.at_level("WARNING", logger="app.risk_model"):
        loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "trained"
    assert "scikit-learn" in caplog.text


def test_a_stale_file_whose_retraining_fails_falls_back_to_rules(tmp_path, monkeypatch):
    stale_bundle(tmp_path, "0.24.2")

    def broken():
        raise RuntimeError("no scikit-learn here")

    monkeypatch.setattr(risk_model, "default_classifier", broken)
    loaded = risk_model.RiskModel.load(settings_for(tmp_path))
    assert loaded.status == "absent"
    assert not loaded.usable


def test_health_reports_a_stale_file_as_trained(tmp_path):
    stale_bundle(tmp_path, "0.24.2")
    body = client_for(tmp_path).get("/health").json()
    assert body["riskModel"] == {"status": "trained",
                                 "version": risk_model.MODEL_VERSION}


# --- /health ----------------------------------------------------------------


def test_health_reports_a_model_trained_in_process(tmp_path):
    body = client_for(tmp_path).get("/health").json()
    assert body["riskModel"] == {"status": "trained",
                                 "version": risk_model.MODEL_VERSION}
    # The plan ranker's fields keep their meaning.
    assert body["status"] == "ok"
    assert body["model"] == "absent"
    assert body["mode"] == "rules"


def test_health_reports_a_loaded_model(tmp_path):
    risk_model.save(risk_model.default_classifier(), str(model_file(tmp_path)))
    body = client_for(tmp_path).get("/health").json()
    assert body["riskModel"] == {"status": "loaded",
                                 "version": risk_model.MODEL_VERSION}


def test_health_reports_an_absent_model(tmp_path):
    model_file(tmp_path).write_bytes(b"garbage")
    body = client_for(tmp_path).get("/health").json()
    assert body["riskModel"] == {"status": "absent", "version": None}


# --- POST /injury-risk ------------------------------------------------------


def test_the_old_request_body_still_works(tmp_path):
    response = client_for(tmp_path).post(
        "/injury-risk", json={"checkins": [], "load": 35.0, "injuryHistory": []},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == CONTRACT_KEYS
    assert body["trainingLoadScore"] >= 17.5
    assert body["riskLevel"] == "low"
    assert body["loadPct"] == 35.0


def test_the_response_matches_the_contract(tmp_path):
    response = client_for(tmp_path).post("/injury-risk", json={
        "checkins": [{"sleepQuality": "poor", "muscleSoreness": "mild",
                      "energy": "moderate", "stress": "low"}] * 3,
        "load": 35.0,
        "injuryHistory": [{"injuryId": 3, "regionGroup": "knee"},
                          {"injuryId": 5, "regionGroup": "lower_back"}],
        "recentPain": "moderate",
    })
    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == CONTRACT_KEYS
    assert body["riskLevel"] in ("low", "moderate", "high")
    assert 0.0 <= body["trainingLoadScore"] <= 100.0
    assert body["source"] in ("model", "rules")
    assert body["modelVersion"] == risk_model.MODEL_VERSION
    assert body["loadPct"] == 35.0
    # Rules: 17.5 load + 23 recovery + 10 injuries + 10 pain = 60.5.
    assert body["trainingLoadScore"] >= 60.5

    drivers = body["drivers"]
    assert drivers == [
        {"key": "load", "value": 35.0},
        {"key": "sleep", "value": "poor"},
        {"key": "injury_history", "value": 2},
    ]
    assert all(set(d) == {"key", "value"} and d["key"] in DRIVER_KEYS
               for d in drivers)


def test_a_calm_day_has_no_drivers(tmp_path):
    body = client_for(tmp_path).post("/injury-risk", json={
        "checkins": [{"sleepQuality": "excellent", "muscleSoreness": "none",
                      "energy": "high", "stress": "very_low"}],
        "load": 0.0,
    }).json()
    assert body["drivers"] == []
    assert body["riskLevel"] == "low"


def test_an_ordinary_day_has_no_drivers(tmp_path):
    # Everyday answers and a slightly bigger week: each adds a few points, but
    # none reaches the 5-point driver bar, so the app says nothing stands out.
    body = client_for(tmp_path).post("/injury-risk", json={
        "checkins": [{"sleepQuality": "good", "muscleSoreness": "mild",
                      "energy": "moderate", "stress": "low"}] * 3,
        "load": 8.0,
    }).json()
    assert body["source"] in ("model", "rules")
    assert body["drivers"] == []


def test_a_corrupt_model_serves_the_rules_with_source_rules(tmp_path):
    model_file(tmp_path).write_bytes(b"garbage")
    body = client_for(tmp_path).post("/injury-risk", json={
        "load": 0.0, "injuryHistory": [{"injuryId": 1}] * 3,
    }).json()
    assert body["source"] == "rules"
    assert body["modelVersion"] is None
    assert body["trainingLoadScore"] == 10.0


def test_a_model_failing_mid_request_still_answers(tmp_path):
    client = client_for(tmp_path)

    class Broken:
        def predict_proba(self, X):
            raise RuntimeError("boom")

    client.app.state.risk_model = risk_model.RiskModel(
        status="loaded", classifier=Broken(), version=risk_model.MODEL_VERSION)
    response = client.post("/injury-risk", json={"load": 35.0})
    assert response.status_code == 200
    assert response.json()["source"] == "rules"
    assert response.json()["trainingLoadScore"] == 17.5


def test_past_injuries_reach_the_model_through_the_endpoint(tmp_path):
    body = client_for(tmp_path).post("/injury-risk", json={
        "load": 0.0, "injuryHistory": [{"injuryId": 1}] * 3,
    }).json()
    assert body["source"] == "model"
    assert body["trainingLoadScore"] > 10.0


@pytest.mark.parametrize("content", [
    '{"checkins": [], "load": NaN, "injuryHistory": []}',
    '{"checkins": [], "load": Infinity}',
])
def test_a_non_finite_load_is_still_a_422(tmp_path, content):
    response = client_for(tmp_path).post(
        "/injury-risk", content=content,
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 422


def test_a_check_in_answer_that_is_not_a_string_is_ignored_not_a_500(tmp_path):
    # checkins are plain dicts, so a list or object can arrive as an answer.
    # It is unhashable, and looking it up in a scoring table used to raise.
    response = client_for(tmp_path).post("/injury-risk", json={
        "load": 20.0,
        "checkins": [{"sleepQuality": ["poor"], "muscleSoreness": {"a": 1},
                      "energy": "low", "stress": None}],
    })
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["trainingLoadScore"] >= 17.0   # 10 load + 7 energy
    assert [d["key"] for d in body["drivers"]] == ["load", "energy"]
