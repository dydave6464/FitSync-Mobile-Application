import numpy as np
import pytest

from app import ranker_data as rd
from app import ranker_features as rf
from app import ranker_model as rm

COL = {name: i for i, name in enumerate(rf.FEATURES)}


@pytest.fixture(scope="module")
def model():
    return rm.default_classifier()


def situation(**changes):
    base = {"mainGoal": "build_muscle", "fitnessLevel": "intermediate",
            "trainingLocation": "home_gym", "sessionLengthMin": 60,
            "splitStyle": "full_body", "mark": "first", "beginnerFriendly": True,
            "pickedEquipment": True, "equipmentName": "dumbbell",
            "daysSinceTrained": 7, "timesDone": 1}
    return np.array([rf.encode(dict(base, **changes))])


def p(model, **changes):
    return model.predict_proba(situation(**changes))[0, 1]


def test_versions():
    assert rm.version_for(0) == "ranker-rf-sim-1"
    assert rm.version_for(12) == "ranker-rf-sim+real-1"


def test_the_forest_is_monotonic_in_the_constrained_features(model):
    for name, direction in rf.MONOTONIC.items():
        key = {"times_done": "timesDone", "times_skipped": "timesSkipped",
               "times_swapped": "timesSwapped", "days_since_trained": "daysSinceTrained",
               "picked_equipment": "pickedEquipment"}.get(name)
        if key is None:
            continue
        values = [0, 1, 2, 3, 5] if name != "picked_equipment" else [False, True]
        scores = [p(model, **{key: v}) for v in values]
        steps = np.diff(scores)
        assert (steps * direction >= -1e-12).all(), (name, scores)


def test_the_assumptions_show_in_the_trained_model(model):
    assert p(model, timesSwapped=2) < p(model) - 0.05
    assert p(model, daysSinceTrained=1) < p(model) - 0.05
    assert p(model, timesDone=4) > p(model) + 0.02


def test_bundle_records_what_produced_it(model):
    import sklearn
    b = rm.bundle(model, real_rows=0)
    assert b["version"] == "ranker-rf-sim-1"
    assert b["features"] == list(rf.FEATURES)
    assert b["sklearnVersion"] == sklearn.__version__
    assert b["simulationSeed"] == rd.SEED


def test_cross_validation_groups_by_trainee():
    data = rd.simulate(rows=3000)
    cv = rm.cross_validate(data.X, data.y, groups=data.trainee,
                           evaluate=~data.coverage, k=3)
    assert cv["method"] == "StratifiedGroupKFold"
    assert 0.5 < cv["rocAuc"]["mean"] <= 1.0
    assert cv["rulesTierRocAuc"]["mean"] < cv["rocAuc"]["mean"]
    assert "logLoss" in cv and "accuracy" in cv


def test_reorder_moves_only_within_runs_and_only_to_a_higher_band():
    keys = [("first", 1), ("first", 1), ("first", 1), ("alternative", 1), ("first", 0)]
    scores = [0.50, 0.80, 0.52, 0.99, 0.10]
    order = rm.reorder(keys, scores)
    # The run of three firsts: 0.80 moves up; 0.50 and 0.52 share the
    # 0.50-0.55 band, so they keep their order. The alternative and the
    # body-weight first stay in their places.
    assert order == [1, 0, 2, 3, 4]


@pytest.mark.parametrize("scores,order", [
    ([0.549, 0.551], [1, 0]),   # 0.2 points apart, but across a band edge
    ([0.501, 0.549], [0, 1]),   # 4.8 points apart, but in one band
    ([0.55, 0.60], [1, 0]),     # band edges belong to the higher band
])
def test_reorder_compares_fixed_bands_not_the_gap(scores, order):
    # The rule is floor(score / 0.05), not a minimum gap: what moves an item
    # is landing in a higher 5-point band, however small the difference.
    keys = [("first", 1)] * len(scores)
    assert rm.reorder(keys, scores) == order


def test_reorder_never_merges_two_runs_with_the_same_key():
    keys = [("first", 1), ("alternative", 1), ("first", 1)]
    assert rm.reorder(keys, [0.1, 0.5, 0.9]) == [0, 1, 2]


def test_reorder_of_equal_scores_is_the_identity():
    keys = [("first", 1)] * 4
    assert rm.reorder(keys, [0.6] * 4) == [0, 1, 2, 3]
