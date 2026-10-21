import joblib
import numpy as np
import pytest

from app import ranker_model
from app.catalogue import Candidate, CandidateAttributes
from app.config import Settings
from app.ranker import RankContext, Ranker
from app.schemas import PlanHistory

BASE_ENV = {
    "FITSYNC_DB_HOST": "127.0.0.1", "FITSYNC_DB_PORT": "3306",
    "FITSYNC_DB_USER": "u", "FITSYNC_DB_PASSWORD": "p", "FITSYNC_DB_NAME": "d",
}


def settings_with_model_dir(path):
    return Settings.from_env(dict(BASE_ENV, FITSYNC_MODEL_DIR=str(path)))


# Rules order: three first choices on picked equipment, one alternative, then
# a body-weight first choice for a group the user's equipment cannot train.
CANDIDATES = [
    Candidate(1, "db squat", "quads"),
    Candidate(2, "db lunge", "quads"),
    Candidate(3, "db step-up", "quads"),
    Candidate(4, "goblet squat", "quads"),
    Candidate(5, "pull-up", "lats"),
]
ATTRS = {
    1: CandidateAttributes("first", True, "dumbbell", True),
    2: CandidateAttributes("first", True, "dumbbell", True),
    3: CandidateAttributes("first", True, "dumbbell", True),
    4: CandidateAttributes("alternative", True, "dumbbell", True),
    5: CandidateAttributes("first", True, "body weight", False),
}


def context(history=None):
    return RankContext(
        main_goal="build_muscle", fitness_level="intermediate",
        training_location="home_gym", session_length_min=60,
        split_style="full_body", health_caution=False,
        attributes=ATTRS, history=history or PlanHistory())


class Fixed:
    """A stand-in classifier returning given scores by row order."""
    def __init__(self, scores):
        self.scores = scores

    def predict_proba(self, X):
        s = np.array(self.scores[: len(X)], dtype=float)
        return np.column_stack([1 - s, s])


def ranked_ids(ranker, ctx=None, candidates=CANDIDATES):
    return [c.exercise_id for c in ranker.rank(candidates, ctx if ctx is not None else context())]


def test_no_file_trains_in_process(tmp_path):
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "trained"
    assert ranker.mode == "model"
    assert ranker.version == "ranker-rf-sim-1"


def test_a_saved_bundle_loads(tmp_path):
    ranker_model.save(ranker_model.default_classifier(), str(tmp_path / "plan_ranker.joblib"))
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "loaded" and ranker.version == "ranker-rf-sim-1"


def test_a_bundle_from_another_scikit_learn_is_retrained(tmp_path):
    b = ranker_model.bundle(ranker_model.default_classifier())
    b["sklearnVersion"] = "0.0.1"
    joblib.dump(b, tmp_path / "plan_ranker.joblib")
    assert Ranker.load(settings_with_model_dir(tmp_path)).status == "trained"


@pytest.mark.parametrize("payload", [
    "not a bundle",
    {"model": object(), "features": ["wrong"], "sklearnVersion": "x"},
])
def test_an_unusable_file_serves_rules(tmp_path, payload):
    joblib.dump(payload, tmp_path / "plan_ranker.joblib")
    ranker = Ranker.load(settings_with_model_dir(tmp_path))
    assert ranker.status == "unusable" and ranker.mode == "rules"
    assert ranker.rank(CANDIDATES, context()) == CANDIDATES


def test_without_context_or_model_ranking_is_the_identity():
    assert Ranker(status="absent").rank(CANDIDATES, context()) == CANDIDATES
    assert Ranker(status="trained", classifier=Fixed([0.1] * 5),
                  version="v").rank(CANDIDATES, None) == CANDIDATES


def test_reorders_only_within_a_run_of_equal_mark_and_picked_tier():
    ranker = Ranker(status="trained", classifier=Fixed([0.2, 0.9, 0.5, 0.99, 0.99]), version="v")
    # 1-3 reorder by score; 4 (alternative) and 5 (body weight) stay put.
    assert ranked_ids(ranker) == [2, 3, 1, 4, 5]


def test_close_scores_keep_the_teams_order():
    ranker = Ranker(status="trained", classifier=Fixed([0.61, 0.63, 0.60, 0.1, 0.1]), version="v")
    assert ranked_ids(ranker) == [1, 2, 3, 4, 5]


@pytest.mark.parametrize("scores", [
    [float("nan")] * 5, [1.5] * 5, [-0.1] * 5,
])
def test_nonsense_scores_serve_rules(scores):
    ranker = Ranker(status="trained", classifier=Fixed(scores), version="v")
    assert ranker.rank(CANDIDATES, context()) == CANDIDATES


def test_a_classifier_that_raises_serves_rules():
    class Boom:
        def predict_proba(self, X):
            raise RuntimeError("boom")
    assert Ranker(status="trained", classifier=Boom(), version="v").rank(
        CANDIDATES, context()) == CANDIDATES


def test_a_candidate_without_attributes_serves_rules():
    ctx = context()
    ctx = RankContext(**{**ctx.__dict__, "attributes": {k: v for k, v in ATTRS.items() if k != 2}})
    ranker = Ranker(status="trained", classifier=Fixed([0.1, 0.9, 0.5, 0.1, 0.1]), version="v")
    assert ranker.rank(CANDIDATES, ctx) == CANDIDATES


def test_the_trained_model_moves_a_swapped_out_exercise_down():
    ranker = Ranker.trained_in_process()
    history = PlanHistory.model_validate(
        {"muscleDaysAgo": {"quads": 7}, "exercises": {"1": {"swapped": 3}}})
    order = ranked_ids(ranker, context(history))
    assert order.index(1) > order.index(2) and order.index(1) > order.index(3)
    assert order[3:] == [4, 5]


def test_only_trusted_originals_leave():
    ranker = Ranker(status="trained", classifier=Fixed([0.9, 0.1, 0.1, 0.1, 0.1]), version="v")
    out = ranker.rank(CANDIDATES, context())
    assert all(any(o is c for c in CANDIDATES) for o in out)
    assert sorted(c.exercise_id for c in out) == [1, 2, 3, 4, 5]
