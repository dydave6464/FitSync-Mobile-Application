from app.catalogue import Candidate
from app.config import Settings
from app.ranker import Ranker

BASE_ENV = {
    "FITSYNC_DB_HOST": "127.0.0.1",
    "FITSYNC_DB_PORT": "3306",
    "FITSYNC_DB_USER": "u",
    "FITSYNC_DB_PASSWORD": "p",
    "FITSYNC_DB_NAME": "d",
}


def settings_with_model_dir(path):
    return Settings.from_env(dict(BASE_ENV, FITSYNC_MODEL_DIR=str(path)))


def candidates():
    return [
        Candidate(1, "a", "quads"),
        Candidate(2, "b", "pectorals"),
        Candidate(3, "c", "lats"),
    ]


def test_scikit_learn_is_installed():
    # The manuscript specifies scikit-learn as the ML stack, and the model slot
    # cannot unpickle a real model without it -- joblib.load would raise
    # ModuleNotFoundError and the ranker would degrade to rules silently, which
    # looks identical to working correctly. Fail loudly here instead.
    import sklearn

    assert sklearn.__version__


def test_a_real_sklearn_model_round_trips_through_the_slot(tmp_path):
    # Proves the slot works end to end with the specified library, not just with
    # the hand-written doubles below.
    import joblib
    from sklearn.linear_model import LogisticRegression

    joblib.dump(LogisticRegression(), tmp_path / "plan_ranker.joblib")
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "loaded"
    assert ranker.mode == "model"
    # A bare LogisticRegression has no .rank(), so ranking falls back to the
    # rules order rather than raising -- the designed failure, section 8.
    assert ranker.rank(candidates()) == candidates()


def test_an_absent_model_reports_absent_and_serves_rules(tmp_path):
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "absent"
    assert ranker.mode == "rules"


def test_with_no_model_ranking_is_the_identity(tmp_path):
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.rank(candidates()) == candidates()


def test_a_corrupt_model_falls_back_to_rules_rather_than_raising(tmp_path):
    # A user finishing onboarding must never see a 502 because a model file
    # went bad. Degrading to rules is the designed failure -- section 8.
    (tmp_path / "plan_ranker.joblib").write_bytes(b"not a joblib file")
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "unusable"
    assert ranker.mode == "rules"
    assert ranker.rank(candidates()) == candidates()


def test_a_missing_model_directory_is_not_an_error(tmp_path):
    ranker = Ranker.load(settings_with_model_dir(tmp_path / "nope"))
    assert ranker.status == "absent"
    assert ranker.rank(candidates()) == candidates()


def test_the_ranker_may_never_add_a_candidate(tmp_path):
    # The safety invariant, enforced in code rather than trusted to training:
    # a model regression can make a plan duller, never unsafe.
    class Sneaky:
        def rank(self, items):
            return list(items) + [Candidate(99, "smuggled deadlift", "glutes")]

    ranker = Ranker(status="loaded", model=Sneaky())
    result = ranker.rank(candidates())
    assert Candidate(99, "smuggled deadlift", "glutes") not in result
    assert result == candidates()


def test_a_model_cannot_substitute_its_own_object_for_a_real_candidate():
    # The invariant that matters: `name` is what savePlan resolves and what the
    # user is prescribed. A model spoofing a legitimate exercise_id must not be
    # able to put its own name into the plan.
    class Fake:
        exercise_id = 1
        name = "barbell deadlift"
        muscle_group = "glutes"

    class Spoofer:
        def rank(self, items):
            return [Fake()]

    result = Ranker(status="loaded", model=Spoofer()).rank(candidates())
    assert result == [Candidate(1, "a", "quads")]
    assert all(isinstance(c, Candidate) for c in result)
    assert "barbell deadlift" not in [c.name for c in result]


def test_a_model_returning_none_degrades_to_rules():
    class ReturnsNone:
        def rank(self, items):
            return None

    assert Ranker(status="loaded", model=ReturnsNone()).rank(candidates()) == candidates()


def test_a_model_returning_a_non_iterable_degrades_to_rules():
    class ReturnsInt:
        def rank(self, items):
            return 42

    assert Ranker(status="loaded", model=ReturnsInt()).rank(candidates()) == candidates()


def test_a_model_returning_a_subset_is_honoured(tmp_path):
    class Picky:
        def rank(self, items):
            return [items[2], items[0]]

    ranker = Ranker(status="loaded", model=Picky())
    assert ranker.rank(candidates()) == [Candidate(3, "c", "lats"),
                                         Candidate(1, "a", "quads")]


def test_a_model_that_raises_falls_back_to_the_rules_order(tmp_path):
    class Broken:
        def rank(self, items):
            raise RuntimeError("model exploded")

    ranker = Ranker(status="loaded", model=Broken())
    assert ranker.rank(candidates()) == candidates()
