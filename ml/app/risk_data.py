"""Simulated starter data for the injury-risk model.

FitSync has no injury outcomes to learn from yet: a handful of check-ins and no
pain reports. So the model in app/risk_model.py is trained on SIMULATED
user-days, generated here from the risk factors the manuscript cites:

- Tsilimigkras et al. 2024: acute surges in training load are prominent
  predictors of injury. Load is therefore the strongest factor below.
- Xu et al. 2025: in random-forest models, prior injury, training intensity and
  recovery time are the best predictors. Past injuries and recent pain are
  therefore strong factors, and poor recovery (sleep, soreness, energy, stress)
  a moderate one.

Nothing here is observed. The marginal distributions are judgement calls about
what a gym user's week looks like, and the coefficients encode the direction
and rough ordering of the published factors, not their measured sizes. The
label's absolute rate is set so that 100 x probability lines up with the rules'
0-100 score (app/risk.py) -- it is not an epidemiological injury rate. What a
model trained on this can honestly claim is that it reproduces those factors
consistently; it is retrained on real check-in outcomes as they accumulate
(see app/train_risk.py, --real).

A fifth of the rows are "coverage" rows spread evenly over the feature space,
so the forest sees the rare risky combinations everyday rows almost never
produce. They share the same probability model; see COVERAGE_SHARE.

Every feature is coded so that a higher value is riskier, which is what lets
the model be constrained to be monotonic in each of them.
"""
from dataclasses import dataclass

import numpy as np

# The default seed and size. Same seed, same rows: the committed
# cross-validation report and the in-process model are reproducible from these.
SEED = 20261018
ROWS = 30000

# Model inputs, in column order. The four check-in answers are ordinal
# positions (0 = best, 3 = worst) averaged over the 3-day window, so a value is
# a multiple of 1/3. load_pct is the training-load index (percent above the
# usual week, 0-130; server/src/db/training-load.js). injury_count is the
# number of reported injuries (0-3; more count as 3). recent_pain is the worst
# pain reported in the last 14 days (0 = none ... 3 = severe).
FEATURES = (
    "sleep", "soreness", "energy", "stress",
    "load_pct", "injury_count", "recent_pain",
)

# Each scale best -> worst, so the index is the ordinal value. These are the
# same answer strings the app sends and app/risk.py scores.
SLEEP_ORDER = ("excellent", "good", "fair", "poor")
SORENESS_ORDER = ("none", "mild", "moderate", "severe")
ENERGY_ORDER = ("high", "moderate", "low", "very_low")
STRESS_ORDER = ("very_low", "low", "moderate", "high")
PAIN_ORDER = ("none", "mild", "moderate", "severe")

CHECKIN_ORDERS = (
    ("sleepQuality", SLEEP_ORDER),
    ("muscleSoreness", SORENESS_ORDER),
    ("energy", ENERGY_ORDER),
    ("stress", STRESS_ORDER),
)

LOAD_MAX = 130.0
INJURY_MAX = 3
WINDOW_DAYS = 3

# --- How often each answer is given, best -> worst --------------------------
# Most nights are good or fair; a poor night is about one in ten.
SLEEP_P = (0.20, 0.45, 0.25, 0.10)
# Lifters are often a little sore; severe soreness is uncommon.
SORENESS_P = (0.30, 0.40, 0.22, 0.08)
ENERGY_P = (0.25, 0.45, 0.22, 0.08)
STRESS_P = (0.20, 0.40, 0.30, 0.10)
# About a third of users report a past injury, few report more than one.
INJURY_P = (0.65, 0.22, 0.09, 0.04)
# Most users report no pain after recent sessions.
PAIN_P = (0.75, 0.15, 0.07, 0.03)

# The load index: most weeks are at or below the usual week (index 0), some run
# a little over it, and about one in ten is a real surge.
LOAD_USUAL_SHARE = 0.65
LOAD_OVER_SHARE = 0.25          # the rest are surges
LOAD_OVER_MEAN = 12.0           # exponential mean of a slightly-busier week
LOAD_SURGE_RANGE = (30.0, LOAD_MAX)

# Coverage rows. Realistic marginals make the risky combinations vanishingly
# rare -- three worst days in a row on all four questions is about one in a
# million -- and a forest cannot learn a region it never sees: it would read an
# unseen corner as its nearest busy neighbour and badly underestimate it. So
# this share of rows is drawn evenly across the whole feature space instead.
# It changes WHICH days the forest sees, not the chance of injury it learns for
# any given day: every row's label comes from the same probability model below.
# These rows are marked (SimulatedData.coverage) so the everyday rows can still
# be checked against what a gym user's week looks like.
COVERAGE_SHARE = 0.2

# --- The probability model ---------------------------------------------------
# Expected risk, in points on the rules' 0-100 scale, is a sum of terms; the
# chance of an injury within the week is that many percent, after noise.
#
# Background risk on a perfect day: training is never risk-free.
BASELINE = 1.0
# Load surge, the strongest factor (Tsilimigkras et al. 2024): 0.4 points per
# percent above the usual week, so the biggest surge (130%) adds 52 -- more
# than any other single factor can, yet well short of the High threshold (70)
# on its own. The rules use 0.5 per percent. Less here because the forest is
# constrained to be monotonic, and where the data thins out at the top of the
# load range that constraint lets a leaf's average (days with ordinary,
# slightly-worse recovery) stand for a perfectly rested day, overestimating it
# by up to about eight points. 0.4 keeps "a big week alone can't make it High"
# true of the trained model with room to spare.
LOAD_PER_PCT = 0.40
# Prior injury (Xu et al. 2025): 6 points each, up to 18 for three.
INJURY_PER = 6.0
# Recent pain is current, so it weighs more than one old injury; severe pain
# (22) outweighs three.
PAIN_POINTS = (0.0, 6.0, 12.0, 22.0)
# Poor recovery, a moderate factor: coefficient x (3-day mean ordinal)^2. Squared
# because one fair night is close to normal while repeated poor nights are not --
# the rules' tables are convex in the same way (sleep 0/2/8/15). Soreness is
# weighted most, as the most direct sign of under-recovered tissue, then sleep,
# energy and stress. All four at their worst add 42.3 points: a very rough
# stretch alone reaches Moderate, never High.
RECOVERY_COEF = {"sleep": 1.3, "soreness": 1.6, "energy": 1.0, "stress": 0.8}
# Unmeasured factors (technique, warm-up, individual susceptibility): normal
# noise on the expected risk, in points.
NOISE_SD = 8.0
# The probability is kept off 0 and 1: no day is certain either way.
P_MIN = 0.01
P_MAX = 0.95


@dataclass(frozen=True)
class SimulatedData:
    X: np.ndarray            # (rows, len(FEATURES)) floats
    y: np.ndarray            # (rows,) 0/1: injured within the week
    probability: np.ndarray  # (rows,) the chance each label was drawn with
    coverage: np.ndarray     # (rows,) True for a coverage row, False for everyday
    answers: np.ndarray      # (rows, WINDOW_DAYS, 4) per-day ordinal answers
    seed: int
    rows: int


def expected_risk(X: np.ndarray) -> np.ndarray:
    """Expected risk in points (0-100 scale) for each row, before noise.

    Inputs are clipped to their ranges first, so a row outside them is read as
    the nearest valid one.
    """
    X = np.asarray(X, dtype=float)
    col = {name: X[:, i] for i, name in enumerate(FEATURES)}
    risk = np.full(X.shape[0], BASELINE)
    risk += LOAD_PER_PCT * np.clip(col["load_pct"], 0.0, LOAD_MAX)
    risk += INJURY_PER * np.clip(col["injury_count"], 0, INJURY_MAX)
    pain = np.clip(np.rint(col["recent_pain"]), 0, len(PAIN_POINTS) - 1).astype(int)
    risk += np.asarray(PAIN_POINTS)[pain]
    for name, coef in RECOVERY_COEF.items():
        risk += coef * np.clip(col[name], 0.0, 3.0) ** 2
    return risk


def simulate(rows: int = ROWS, seed: int = SEED) -> SimulatedData:
    rng = np.random.default_rng(seed)
    coverage = rng.random(rows) < COVERAGE_SHARE

    # Everyday rows: each answer drawn independently per day from its
    # distribution above.
    answers = np.stack(
        [rng.choice(4, size=(rows, WINDOW_DAYS), p=p)
         for p in (SLEEP_P, SORENESS_P, ENERGY_P, STRESS_P)],
        axis=2,
    )
    # Coverage rows: one centre picked evenly from 0-3 for all four questions
    # (a rough stretch is usually rough on every one of them, and drawing them
    # separately left "bad on all four" as rare as in everyday rows), then each
    # answer on each day within one step of it, so the 3-day means reach every
    # value including the extremes.
    centre = rng.integers(0, 4, size=(rows, 1, 1))
    step = rng.choice((-1, 0, 0, 1), size=(rows, WINDOW_DAYS, 4))
    spread = np.clip(centre + step, 0, 3)
    answers = np.where(coverage[:, None, None], spread, answers)
    recovery = answers.mean(axis=1)

    kind = rng.choice(3, size=rows,
                      p=(LOAD_USUAL_SHARE, LOAD_OVER_SHARE,
                         1.0 - LOAD_USUAL_SHARE - LOAD_OVER_SHARE))
    over = rng.exponential(LOAD_OVER_MEAN, size=rows)
    surge = rng.uniform(*LOAD_SURGE_RANGE, size=rows)
    load = np.where(kind == 0, 0.0, np.where(kind == 1, over, surge))
    load = np.where(coverage, rng.uniform(0.0, LOAD_MAX, size=rows), load)
    # Two decimals, as training-load.js reports it.
    load = np.round(np.clip(load, 0.0, LOAD_MAX), 2)

    injuries = np.where(coverage, rng.integers(0, 4, size=rows),
                        rng.choice(4, size=rows, p=INJURY_P))
    pain = np.where(coverage, rng.integers(0, 4, size=rows),
                    rng.choice(4, size=rows, p=PAIN_P))

    X = np.column_stack([recovery, load, injuries, pain]).astype(float)
    noisy = expected_risk(X) + rng.normal(0.0, NOISE_SD, size=rows)
    probability = np.clip(noisy / 100.0, P_MIN, P_MAX)
    y = (rng.random(rows) < probability).astype(int)

    return SimulatedData(X=X, y=y, probability=probability, coverage=coverage,
                         answers=answers, seed=seed, rows=rows)


def request_for(data: SimulatedData, index: int) -> dict:
    """The /injury-risk body one simulated row stands for."""
    checkins = [
        {field: order[int(data.answers[index, day, k])]
         for k, (field, order) in enumerate(CHECKIN_ORDERS)}
        for day in range(WINDOW_DAYS)
    ]
    row = data.X[index]
    return {
        "checkins": checkins,
        "load": float(row[FEATURES.index("load_pct")]),
        "injuryHistory": [{"injuryId": i + 1}
                          for i in range(int(row[FEATURES.index("injury_count")]))],
        "recentPain": PAIN_ORDER[int(row[FEATURES.index("recent_pain")])],
    }


def rules_scores(data: SimulatedData) -> np.ndarray:
    """What the rules (app/risk.py) score each simulated day, from its answers.

    Scored by the real rules function rather than a copy of its formula, so the
    level agreement in the cross-validation report measures against exactly
    what the service would floor at.
    """
    from app.risk import rules_score
    from app.schemas import InjuryRiskRequest

    return np.array([
        rules_score(InjuryRiskRequest.model_validate(request_for(data, i)))
        for i in range(data.rows)
    ])
