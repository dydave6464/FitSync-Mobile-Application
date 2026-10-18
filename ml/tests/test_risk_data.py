"""The simulated starter data behind the injury-risk model.

It is simulated, not observed: these tests check that it is reproducible, that
its days look like a gym user's, and that its probability model follows the
cited risk factors on the same scale as the rules. They cannot check that it
matches real injuries, and nothing here claims it does.
"""
import numpy as np
import pytest

from app import risk_data
from app.risk import level_for

ROWS = 6000


@pytest.fixture(scope="module")
def data():
    return risk_data.simulate(rows=ROWS, seed=risk_data.SEED)


def column(data, name):
    return data.X[:, risk_data.FEATURES.index(name)]


def test_the_same_seed_gives_identical_rows(data):
    again = risk_data.simulate(rows=ROWS, seed=risk_data.SEED)
    assert np.array_equal(data.X, again.X)
    assert np.array_equal(data.y, again.y)


def test_a_different_seed_gives_different_rows(data):
    other = risk_data.simulate(rows=ROWS, seed=risk_data.SEED + 1)
    assert not np.array_equal(data.X, other.X)


def test_the_feature_columns_are_the_documented_ones(data):
    assert risk_data.FEATURES == (
        "sleep", "soreness", "energy", "stress",
        "load_pct", "injury_count", "recent_pain",
    )
    assert data.X.shape == (ROWS, len(risk_data.FEATURES))
    assert data.y.shape == (ROWS,)
    assert set(np.unique(data.y)) <= {0, 1}


def test_every_feature_stays_in_its_range(data):
    for name in ("sleep", "soreness", "energy", "stress"):
        values = column(data, name)
        assert values.min() >= 0 and values.max() <= 3
        # A 3-day mean of whole-number answers.
        assert np.allclose(values * 3, np.round(values * 3))
    load = column(data, "load_pct")
    assert load.min() >= 0 and load.max() <= 130
    assert set(np.unique(column(data, "injury_count"))) <= {0, 1, 2, 3}
    assert set(np.unique(column(data, "recent_pain"))) <= {0, 1, 2, 3}


def test_most_days_look_normal(data):
    load = column(data, "load_pct")
    # Most weeks are at or near the usual week, and a big surge is uncommon.
    assert np.median(load) == 0
    assert (load > 50).mean() < 0.12
    # Most users report no past injury and no recent pain.
    assert (column(data, "injury_count") == 0).mean() > 0.55
    assert (column(data, "recent_pain") == 0).mean() > 0.65
    # A typical night is good or fair, not poor.
    assert 0.6 < np.median(column(data, "sleep")) < 1.7


def test_the_label_rate_is_in_a_plausible_band(data):
    assert 0.05 < data.y.mean() < 0.25


def test_the_probabilities_line_up_with_the_rules_scale(data):
    # A rules-scored High day should be a high-probability day here, and a Low
    # day a low-probability one; otherwise 100 x probability would not mean
    # the same thing as the rules' 0-100 score it is compared against.
    levels = np.array([level_for(s) for s in risk_data.rules_scores(data)])
    assert (levels == "high").sum() >= 10
    assert data.probability[levels == "high"].mean() >= 0.6
    assert data.probability[levels == "low"].mean() <= 0.2
    moderate = data.probability[levels == "moderate"].mean()
    assert 0.3 <= moderate <= 0.7


def factor_swing(name, low, high):
    base = np.zeros((1, len(risk_data.FEATURES)))
    raised = base.copy()
    base[0, risk_data.FEATURES.index(name)] = low
    raised[0, risk_data.FEATURES.index(name)] = high
    return float(risk_data.expected_risk(raised)[0] - risk_data.expected_risk(base)[0])


def test_load_surges_weigh_most_then_injury_and_pain_then_recovery():
    # Tsilimigkras et al. 2024: acute load surges are prominent predictors.
    # Xu et al. 2025: prior injury and recovery among the best predictors.
    load = factor_swing("load_pct", 0, 130)
    pain = factor_swing("recent_pain", 0, 3)
    injury = factor_swing("injury_count", 0, 3)
    recovery = [factor_swing(n, 0, 3) for n in ("sleep", "soreness", "energy", "stress")]
    assert load > pain and load > injury
    assert min(pain, injury) > max(recovery)
    assert min(recovery) > 0


def test_one_factor_alone_never_reaches_the_high_threshold():
    # The app says a rough morning or a big week alone can't make it High; the
    # simulation is built so that stays true of what the model learns.
    worst_morning = np.zeros((1, len(risk_data.FEATURES)))
    for name in ("sleep", "soreness", "energy", "stress"):
        worst_morning[0, risk_data.FEATURES.index(name)] = 3
    biggest_week = np.zeros((1, len(risk_data.FEATURES)))
    biggest_week[0, risk_data.FEATURES.index("load_pct")] = 130
    assert risk_data.expected_risk(worst_morning)[0] < 60
    assert risk_data.expected_risk(biggest_week)[0] < 62


def test_the_expected_risk_never_falls_as_any_factor_worsens():
    rng = np.random.default_rng(1)
    for _ in range(200):
        row = np.array([[rng.integers(0, 10) / 3, rng.integers(0, 10) / 3,
                         rng.integers(0, 10) / 3, rng.integers(0, 10) / 3,
                         rng.uniform(0, 130), rng.integers(0, 4), rng.integers(0, 4)]])
        row[0, :4] = np.minimum(row[0, :4], 3)
        before = risk_data.expected_risk(row)[0]
        for index, step in enumerate((1 / 3, 1 / 3, 1 / 3, 1 / 3, 10, 1, 1)):
            worse = row.copy()
            worse[0, index] += step
            assert risk_data.expected_risk(worse)[0] >= before
