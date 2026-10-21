import logging

from app.schemas import PlanHistory, ProfileRequest, parse_history


def test_a_good_history_parses():
    h = parse_history({"muscleDaysAgo": {"quads": 2},
                       "exercises": {"12": {"done": 3, "skipped": 1, "swapped": 0}}})
    assert h.muscleDaysAgo == {"quads": 2}
    assert h.exercises["12"].done == 3


def test_missing_or_malformed_history_is_empty_not_an_error(caplog):
    caplog.set_level(logging.WARNING, logger="app.schemas")
    assert parse_history(None) == PlanHistory()
    assert caplog.records == []  # no history is normal, not a fault

    for raw in ("x", 5, [], {"muscleDaysAgo": "nope"},
                {"exercises": {"1": {"done": "many"}}}):
        caplog.clear()
        assert parse_history(raw) == PlanHistory()
        warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
        assert len(warnings) == 1, raw


def test_a_malformed_history_is_logged_by_location_without_its_values(caplog):
    caplog.set_level(logging.WARNING, logger="app.schemas")
    # Shapes a server-side regression could send: a null, a fractional day
    # count, a string count. Only the count and the paths may be logged.
    raw = {"muscleDaysAgo": {"quads": None, "glutes": 2.5},
           "exercises": {"7": {"done": "SECRET-VALUE"}}}
    assert parse_history(raw) == PlanHistory()
    (record,) = caplog.records
    message = record.getMessage()
    assert "3 error" in message
    assert "muscleDaysAgo.quads" in message
    assert "muscleDaysAgo.glutes" in message
    assert "exercises.7.done" in message
    assert "SECRET-VALUE" not in message
    assert "2.5" not in message


def test_the_profile_accepts_any_history_value():
    assert ProfileRequest.model_validate({"history": "garbage"}).history == "garbage"
    assert ProfileRequest.model_validate({}).history is None
