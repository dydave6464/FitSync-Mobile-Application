from app.schemas import PlanHistory, ProfileRequest, parse_history


def test_a_good_history_parses():
    h = parse_history({"muscleDaysAgo": {"quads": 2},
                       "exercises": {"12": {"done": 3, "skipped": 1, "swapped": 0}}})
    assert h.muscleDaysAgo == {"quads": 2}
    assert h.exercises["12"].done == 3


def test_missing_or_malformed_history_is_empty_not_an_error():
    for raw in (None, "x", 5, [], {"muscleDaysAgo": "nope"},
                {"exercises": {"1": {"done": "many"}}}):
        assert parse_history(raw) == PlanHistory()


def test_the_profile_accepts_any_history_value():
    assert ProfileRequest.model_validate({"history": "garbage"}).history == "garbage"
    assert ProfileRequest.model_validate({}).history is None
