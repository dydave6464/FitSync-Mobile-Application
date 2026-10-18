"""The scikit-learn injury-risk model and how its score meets the rules' floor.

The model is trained on simulated data (app/risk_data.py). These tests check
that it learns that simulation, that it can never lower the rules' score, and
that it moves the right way when an input worsens. They say nothing about
accuracy on real injuries, which there is no data to measure yet.
"""

import numpy as np
import pytest

from app import risk, risk_data, risk_model
from app.schemas import InjuryRiskRequest

GOOD = {"sleepQuality": "good", "muscleSoreness": "mild",
        "energy": "moderate", "stress": "low"}
WORST = {"sleepQuality": "poor", "muscleSoreness": "severe",
         "energy": "very_low", "stress": "high"}
BEST = {"sleepQuality": "excellent", "muscleSoreness": "none",
        "energy": "high", "stress": "very_low"}


@pytest.fixture(scope="module")
def model():
    # The same in-process model the service trains when no file is on disk.
    return risk_model.RiskModel(
        status="trained", classifier=risk_model.default_classifier(),
        version=risk_model.MODEL_VERSION,
    )


def request(**fields):
    return InjuryRiskRequest(**fields)


def injuries(n):
    return [{"injuryId": i + 1} for i in range(n)]


# --- features ---------------------------------------------------------------


def test_features_average_the_window_as_ordinals_with_higher_riskier():
    row = risk_model.features_for(request(
        load=35.0,
        checkins=[dict(GOOD, sleepQuality="poor"), dict(GOOD, sleepQuality="fair")],
        injuryHistory=injuries(2), recentPain="moderate",
    ))
    assert row.shape == (1, len(risk_data.FEATURES))
    values = dict(zip(risk_data.FEATURES, row[0]))
    assert values["sleep"] == pytest.approx(2.5)        # poor 3, fair 2
    assert values["soreness"] == pytest.approx(1.0)     # mild
    assert values["energy"] == pytest.approx(1.0)       # moderate
    assert values["stress"] == pytest.approx(1.0)       # low
    assert values["load_pct"] == 35.0
    assert values["injury_count"] == 2
    assert values["recent_pain"] == 2


def test_features_clip_to_the_training_ranges_and_read_unknowns_as_best():
    row = risk_model.features_for(request(
        load=400.0, checkins=[{"sleepQuality": "banana"}, {}],
        injuryHistory=injuries(7), recentPain="banana",
    ))
    values = dict(zip(risk_data.FEATURES, row[0]))
    assert values["load_pct"] == 130.0
    assert values["injury_count"] == 3
    assert values["recent_pain"] == 0
    assert values["sleep"] == 0 and values["soreness"] == 0


def test_no_check_ins_read_as_nothing_reported():
    row = risk_model.features_for(request(load=-10.0))
    assert np.array_equal(row, np.zeros((1, len(risk_data.FEATURES))))


# --- training and cross-validation -----------------------------------------


@pytest.fixture(scope="module")
def cv():
    data = risk_data.simulate(rows=10000, seed=risk_data.SEED)
    return risk_model.cross_validate(
        data.X, data.y, rules_scores=risk_data.rules_scores(data),
        evaluate=~data.coverage,
    )


def test_cross_validation_is_stratified_five_fold(cv):
    assert cv["method"] == "StratifiedKFold"
    assert cv["k"] == 5
    assert len(cv["rocAuc"]["folds"]) == 5


def test_held_out_metrics_score_only_the_everyday_rows(cv):
    # The coverage rows are spread evenly and lean risky; scoring them would
    # flatter the AUC with days that are easy to tell apart.
    assert cv["evaluatedRows"] < cv["rows"]
    assert 0.75 < cv["evaluatedRows"] / cv["rows"] < 0.85


def test_the_model_ranks_held_out_simulated_days_clearly_better_than_chance(cv):
    # The simulation's own noise caps what any model can reach: ranking by the
    # noise-free expected risk scores only about 0.72 on everyday rows.
    assert cv["rocAuc"]["mean"] > 0.65
    assert min(cv["rocAuc"]["folds"]) > 0.6


def test_the_model_beats_a_constant_guess_on_the_brier_score(cv):
    # A constant guess at the base rate scores p(1 - p); a model that has
    # learned anything must do better on held-out folds.
    base = cv["positiveRate"]
    assert cv["brier"]["mean"] < base * (1 - base)


def test_level_agreement_with_the_rules_is_reported_per_fold(cv):
    agreement = cv["levelAgreementWithRules"]
    assert len(agreement["folds"]) == 5
    assert 0.5 < agreement["mean"] <= 1.0
    assert 0.0 <= cv["shareRaisedByModel"]["mean"] < 0.5


def test_the_classifier_is_a_monotonic_random_forest():
    clf = risk_model.default_classifier()
    assert type(clf).__name__ == "RandomForestClassifier"
    assert list(clf.monotonic_cst) == [1] * len(risk_data.FEATURES)


def test_the_saved_model_stays_small(tmp_path):
    path = tmp_path / risk_model.MODEL_FILENAME
    risk_model.save(risk_model.default_classifier(), str(path))
    assert path.stat().st_size < 2 * 1024 * 1024


# --- the final score --------------------------------------------------------


def final(model, **fields):
    return risk_model.estimate(request(**fields), model).trainingLoadScore


def test_the_final_score_is_never_below_the_rules_score(model):
    rng = np.random.default_rng(7)
    answers = [risk_data.SLEEP_ORDER, risk_data.SORENESS_ORDER,
               risk_data.ENERGY_ORDER, risk_data.STRESS_ORDER]
    fields = ("sleepQuality", "muscleSoreness", "energy", "stress")
    for _ in range(300):
        payload = request(
            load=float(rng.uniform(0, 130)),
            checkins=[{f: order[rng.integers(0, 4)] for f, order in zip(fields, answers)}
                      for _ in range(rng.integers(0, 4))],
            injuryHistory=injuries(int(rng.integers(0, 4))),
            recentPain=risk_data.PAIN_ORDER[rng.integers(0, 4)],
        )
        combined = risk_model.estimate(payload, model)
        assert combined.trainingLoadScore >= risk.rules_score(payload)
        assert combined.riskLevel == risk.level_for(combined.trainingLoadScore)


def test_a_higher_load_never_lowers_the_final_score(model):
    scores = [final(model, load=float(load), checkins=[GOOD]) for load in range(0, 131, 5)]
    assert scores == sorted(scores)


@pytest.mark.parametrize("field, order", [
    ("sleepQuality", risk_data.SLEEP_ORDER),
    ("muscleSoreness", risk_data.SORENESS_ORDER),
    ("energy", risk_data.ENERGY_ORDER),
    ("stress", risk_data.STRESS_ORDER),
])
def test_a_worse_check_in_answer_never_lowers_the_final_score(model, field, order):
    for load in (0.0, 40.0, 100.0):
        scores = [final(model, load=load, checkins=[dict(GOOD, **{field: a})])
                  for a in order]
        assert scores == sorted(scores), (field, load, scores)


def test_more_injuries_never_lower_the_final_score(model):
    for load in (0.0, 60.0):
        scores = [final(model, load=load, checkins=[GOOD], injuryHistory=injuries(n))
                  for n in range(5)]
        assert scores == sorted(scores)


def test_worse_pain_never_lowers_the_final_score(model):
    for load in (0.0, 60.0):
        scores = [final(model, load=load, checkins=[GOOD], recentPain=p)
                  for p in risk_data.PAIN_ORDER]
        assert scores == sorted(scores)


def test_a_rough_morning_or_a_big_week_alone_cannot_make_it_high(model):
    # The app's "How to read this" sheet says so; it has to stay true with the
    # model in the loop, not only for the rules.
    assert risk_model.estimate(request(load=0.0, checkins=[WORST]), model).riskLevel != "high"
    assert risk_model.estimate(request(load=130.0, checkins=[BEST]), model).riskLevel != "high"
    assert risk_model.estimate(request(load=130.0), model).riskLevel != "high"


def test_a_bad_stretch_on_a_big_week_with_pain_is_high(model):
    result = risk_model.estimate(request(
        load=110.0, checkins=[WORST, WORST, WORST], injuryHistory=injuries(2),
        recentPain="moderate",
    ), model)
    assert result.riskLevel == "high"


def test_past_injuries_let_the_model_decide(model):
    # Three injuries on an easy week with nothing else reported: the rules cap
    # injuries at 10, while the simulation weighs prior injury more heavily
    # (Xu et al. 2025), so the model's score is the higher one.
    payload = request(load=0.0, injuryHistory=injuries(3))
    result = risk_model.estimate(payload, model)
    assert result.source == "model"
    assert result.modelVersion == risk_model.MODEL_VERSION
    assert result.trainingLoadScore > risk.rules_score(payload) == 10.0
    assert result.riskLevel == risk.level_for(result.trainingLoadScore)


def test_when_the_rules_score_is_higher_the_source_is_rules(model):
    payload = request(load=130.0, checkins=[BEST])
    result = risk_model.estimate(payload, model)
    assert result.trainingLoadScore == risk.rules_score(payload)
    assert result.source == "rules"
    # A model is loaded, so the response still says which one was consulted.
    assert result.modelVersion == risk_model.MODEL_VERSION


def test_drivers_and_load_pct_come_from_the_rules_whichever_side_decided(model):
    payload = request(load=0.0, injuryHistory=injuries(3))
    result = risk_model.estimate(payload, model)
    assert result.source == "model"
    expected = risk.estimate(payload)
    assert result.drivers == expected.drivers
    assert result.loadPct == expected.loadPct


def test_no_model_means_the_rules_alone():
    payload = request(load=35.0, injuryHistory=injuries(1))
    result = risk_model.estimate(payload, risk_model.RiskModel(status="absent"))
    assert result == risk.estimate(payload)


def test_a_model_that_fails_on_a_request_falls_back_to_the_rules():
    class Broken:
        def predict_proba(self, X):
            raise RuntimeError("boom")

    payload = request(load=35.0, injuryHistory=injuries(1))
    broken = risk_model.RiskModel(status="loaded", classifier=Broken(),
                                  version=risk_model.MODEL_VERSION)
    result = risk_model.estimate(payload, broken)
    assert result.source == "rules"
    assert result.modelVersion is None
    assert result.trainingLoadScore == risk.rules_score(payload)


def test_a_model_returning_nonsense_falls_back_to_the_rules():
    class Nonsense:
        def predict_proba(self, X):
            return np.array([[0.0, float("nan")]])

    payload = request(load=35.0)
    result = risk_model.estimate(payload, risk_model.RiskModel(
        status="loaded", classifier=Nonsense(), version="x"))
    assert result.source == "rules"
    assert result.trainingLoadScore == 17.5


def test_the_model_score_is_a_two_decimal_percentage(model):
    score = model.score(request(load=50.0, checkins=[GOOD]))
    assert 0.0 <= score <= 100.0
    assert round(score, 2) == score


def test_a_non_finite_load_is_still_refused(model):
    with pytest.raises(ValueError):
        risk_model.estimate(InjuryRiskRequest.model_construct(
            checkins=[], load=float("nan"), injuryHistory=[], recentPain=None,
        ), model)
