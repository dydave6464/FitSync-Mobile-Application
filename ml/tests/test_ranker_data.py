import numpy as np

from app import ranker_data as rd
from app import ranker_features as rf

COL = {name: i for i, name in enumerate(rf.FEATURES)}


def test_the_default_simulation_is_reproducible():
    a, b = rd.simulate(rows=3000), rd.simulate(rows=3000)
    assert np.array_equal(a.X, b.X) and np.array_equal(a.y, b.y)
    c = rd.simulate(rows=3000, seed=rd.SEED + 1)
    assert not np.array_equal(a.y, c.y)


def test_shapes_and_trainee_groups():
    data = rd.simulate(rows=3000)
    assert data.X.shape == (3000, len(rf.FEATURES))
    assert data.y.shape == data.trainee.shape == data.coverage.shape == (3000,)
    assert set(np.unique(data.y)) <= {0, 1}
    # Each trainee owns CANDIDATES_PER_TRAINEE consecutive rows and one profile.
    per = rd.CANDIDATES_PER_TRAINEE
    assert len(np.unique(data.trainee)) == 3000 // per
    profile_cols = [COL[c] for c in rf.FEATURES[:COL["health_caution"] + 1]]
    for t in np.unique(data.trainee)[:50]:
        rows = data.X[data.trainee == t][:, profile_cols]
        assert (rows == rows[0]).all()


def test_values_stay_in_their_ranges():
    X = rd.simulate(rows=6000).X
    assert X[:, COL["days_since_trained"]].min() >= 0
    assert X[:, COL["days_since_trained"]].max() <= rf.DAYS_CAP
    for c in ("times_done", "times_skipped", "times_swapped"):
        assert 0 <= X[:, COL[c]].min() and X[:, COL[c]].max() <= rf.COUNT_CAP
    assert set(np.unique(X[:, COL["mark"]])) <= {0.0, 1.0}


def test_beginners_and_cautioned_trainees_only_get_beginner_friendly_exercises():
    X = rd.simulate(rows=6000).X
    gentle = (X[:, COL["level"]] < 2) | (X[:, COL["health_caution"]] == 1)
    assert (X[gentle, COL["beginner_friendly"]] == 1).all()


def test_no_location_preference_means_no_location_fit():
    X = rd.simulate(rows=6000).X
    none = X[:, [COL["loc_commercial_gym"], COL["loc_home_gym"], COL["loc_other"]]].sum(axis=1) == 0
    assert (X[none, COL["location_fit"]] == 0).all()


def test_everyday_done_rate_is_about_two_thirds():
    data = rd.simulate()
    rate = data.y[~data.coverage].mean()
    assert 0.55 <= rate <= 0.80, rate


def _logit_with(base_row, **changes):
    row = base_row.copy()
    for name, value in changes.items():
        row[COL[name]] = value
    return rd.expected_logit(row[None, :])[0]


def test_each_assumption_pushes_the_expected_way():
    base = np.array(rf.encode({"daysSinceTrained": 7}), dtype=float)
    plain = _logit_with(base)
    assert _logit_with(base, times_done=2) > plain                  # 1
    assert _logit_with(base, times_skipped=2) < plain               # 2
    assert _logit_with(base, times_swapped=1) < _logit_with(base, times_skipped=1)
    assert _logit_with(base, days_since_trained=1) < plain          # 3
    assert _logit_with(base, days_since_trained=2) > _logit_with(base, days_since_trained=1)
    assert _logit_with(base, days_since_trained=4) == plain
    assert _logit_with(base, picked_equipment=1) > plain            # 4
    assert _logit_with(base, location_fit=1) > plain                # 5


def test_goal_split_length_and_level_have_no_simulated_effect():
    base = np.array(rf.encode({"daysSinceTrained": 7}), dtype=float)
    plain = _logit_with(base)
    for name in ("goal_build_muscle", "goal_lose_weight", "split_upper_lower",
                 "split_cardio_core", "health_caution", "beginner_friendly"):
        assert _logit_with(base, **{name: 1}) == plain, name
    assert _logit_with(base, session_length_min=60) == plain
    assert _logit_with(base, level=2) == plain
    assert _logit_with(base, mark=1) == plain
