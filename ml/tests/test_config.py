import pytest

from app.config import Settings

BASE_ENV = {
    "FITSYNC_DB_HOST": "127.0.0.1",
    "FITSYNC_DB_PORT": "3306",
    "FITSYNC_DB_USER": "fitsync_ml",
    "FITSYNC_DB_PASSWORD": "secret",
    "FITSYNC_DB_NAME": "fitsync",
}


def test_from_env_reads_every_database_field():
    settings = Settings.from_env(BASE_ENV)
    assert settings.db_host == "127.0.0.1"
    assert settings.db_port == 3306
    assert settings.db_user == "fitsync_ml"
    assert settings.db_password == "secret"
    assert settings.db_name == "fitsync"


def test_optional_fields_have_defaults():
    settings = Settings.from_env(BASE_ENV)
    assert settings.model_dir == "models"
    assert settings.log_level == "info"


def test_optional_fields_are_overridable():
    env = dict(BASE_ENV, FITSYNC_MODEL_DIR="/tmp/m", FITSYNC_LOG_LEVEL="debug")
    settings = Settings.from_env(env)
    assert settings.model_dir == "/tmp/m"
    assert settings.log_level == "debug"


def test_missing_credentials_raise_at_construction_naming_every_gap():
    # A generator that cannot read the catalogue 502s every onboarding.
    # Failing at boot is louder than failing per request -- spec section 12.
    env = {"FITSYNC_DB_HOST": "127.0.0.1"}
    with pytest.raises(ValueError) as excinfo:
        Settings.from_env(env)
    message = str(excinfo.value)
    for missing in ("FITSYNC_DB_PORT", "FITSYNC_DB_USER",
                    "FITSYNC_DB_PASSWORD", "FITSYNC_DB_NAME"):
        assert missing in message
    assert "FITSYNC_DB_HOST" not in message


def test_a_non_numeric_port_is_rejected_clearly():
    env = dict(BASE_ENV, FITSYNC_DB_PORT="not-a-number")
    with pytest.raises(ValueError) as excinfo:
        Settings.from_env(env)
    assert "FITSYNC_DB_PORT" in str(excinfo.value)


def test_settings_are_immutable():
    settings = Settings.from_env(BASE_ENV)
    with pytest.raises(Exception):
        settings.db_host = "elsewhere"


from fastapi.testclient import TestClient

from app.main import create_app


def test_health_reports_the_model_is_absent_and_rules_are_serving():
    # Until a trained model exists, rules serve every request. /health says so
    # plainly so an operator can tell which mode is live without reading logs.
    client = TestClient(create_app(Settings.from_env(BASE_ENV)))
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["model"] == "absent"
    assert body["mode"] == "rules"


def test_health_does_not_touch_the_database():
    # /health must answer even when MySQL is down -- it is what a load balancer
    # polls, and a health check that needs the database reports the database.
    settings = Settings.from_env(dict(BASE_ENV, FITSYNC_DB_HOST="203.0.113.1"))
    client = TestClient(create_app(settings))
    assert client.get("/health").status_code == 200
