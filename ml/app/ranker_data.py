"""Simulated starter data for the plan ranker.

FitSync has almost no real record of which exercises people do or skip (dev
DB, 2026-10-21: 58 completed plan workouts from 11 mostly-test accounts and 3
swaps). So the model in app/ranker_model.py is trained on SIMULATED trainees,
generated here from these stated assumptions (spec:
docs/superpowers/specs/2026-10-21-exercise-picking-model-design.md):

1. Having done an exercise before makes doing it again more likely -- past
   behaviour is the strongest predictor of future exercise adherence
   (Rodrigues et al. 2020, 2022; Cid et al. 2025; Conti et al. 2026).
2. Having skipped or swapped it out makes it less likely; a swap, being a
   deliberate rejection, more so than a skip.
3. A muscle trained in the last 72 hours is less likely to be trained again:
   delayed-onset soreness peaks 24-72 h after training (Hotfiel et al. 2018;
   Fu et al. 2024; Kanda et al. 2013).
4. Equipment the trainee picked beats a body-weight fill-in (Jakicic et al.
   1997; Morgan et al. 2016).
5. Equipment that fits where they train is more likely to be used (Collado-
   Mateo et al. 2021; Tross 2024).

Not simulated: a beginner given a non-beginner-friendly exercise (the app
never offers one -- catalogue._BEGINNER), and any effect of goal, level,
session length, split or curated mark. Those stay as inputs, with no effect
here, so real rows can teach them.

Nothing here is observed. The sources study whether people keep exercising,
not which exercise they pick; applying them to single exercises is FitSync's
assumption. The weights below encode direction and rough ordering only. A
model trained on this learns these assumptions, not real people.

Like app/risk_data.py, a share of rows are "coverage" rows spread evenly over
the feature space, so rare combinations (three swaps of an exercise trained
yesterday) are seen. They share the same probability model.
"""
from dataclasses import dataclass

import numpy as np

from app import ranker_features as rf

SEED = 20261021
ROWS = 30000
CANDIDATES_PER_TRAINEE = 6
COVERAGE_SHARE = 0.2

# --- Trainees ----------------------------------------------------------------
GOAL_P = {"general_fitness": 0.25, "lose_weight": 0.25, "build_muscle": 0.25,
          "gain_strength": 0.15, "improve_endurance": 0.10}
LEVEL_P = {"new": 0.30, "beginner": 0.40, "intermediate": 0.30}
LOCATION_P = {"commercial_gym": 0.40, "home_gym": 0.35, "other": 0.10,
              "both": 0.10, None: 0.05}
SPLIT_P = {"full_body": 0.50, "push_pull_legs": 0.20, "upper_lower": 0.20,
           "cardio_core": 0.10}
CAUTION_P = 0.10
LONG_SESSION_GOALS = ("gain_strength", "build_muscle")

# --- Candidates: a snapshot of what a plan can offer (dev DB, 2026-10-21,
# live strength exercises not marked search_only/never): 117 first choices
# (116 beginner-friendly), 195 alternatives (93 beginner-friendly), none
# unmarked. A beginner or cautioned trainee is offered only the 209
# beginner-friendly ones, as catalogue._BEGINNER does.
GENTLE_FIRST_P = 116 / 209
OPEN_FIRST_P = 117 / 312
OPEN_FRIENDLY_GIVEN_FIRST_P = 116 / 117
OPEN_FRIENDLY_GIVEN_ALTERNATIVE_P = 93 / 195
PICKED_P = 0.70
LOCATION_FIT_P = 0.50     # when the location expresses a preference

# --- History -------------------------------------------------------------------
DONE_MEAN = 1.2
SKIPPED_MEAN = 0.4
SWAPPED_MEAN = 0.1
NEVER_TRAINED_P = 0.25

# --- The probability model (log-odds of "did it") ------------------------------
BASE_LOGIT = 0.4         # puts the everyday done rate near two thirds
DONE_PER = 0.35            # assumption 1
SKIPPED_PER = -0.55        # assumption 2
SWAPPED_PER = -1.10        # assumption 2, a swap counts double
# Assumption 3, by days since the muscle was trained: strongest at 1-2 days
# (DOMS peaks 24-72 h), fading by day 3; 4 or more days, nothing. Day 0
# (earlier today) gets the same penalty as days 1-2 rather than a larger one,
# because the monotonic constraint on days_since_trained (+1) needs the
# penalty non-decreasing in days.
REST_PENALTY = (-1.0, -1.0, -1.0, -0.3)
PICKED_BONUS = 0.5         # assumption 4
LOCATION_BONUS = 0.4       # assumption 5
NOISE_SD = 0.5             # on the log-odds: everything unmeasured
P_MIN = 0.02
P_MAX = 0.98

_COL = {name: i for i, name in enumerate(rf.FEATURES)}


@dataclass(frozen=True)
class SimulatedRanking:
    X: np.ndarray            # (rows, len(FEATURES))
    y: np.ndarray            # (rows,) 1 = did it
    probability: np.ndarray  # (rows,) chance each label was drawn with
    coverage: np.ndarray     # (rows,) True for a coverage row
    trainee: np.ndarray      # (rows,) trainee index; CV groups by it
    seed: int
    rows: int


def expected_logit(X: np.ndarray) -> np.ndarray:
    """Log-odds of "did it" for each row, before noise (assumptions 1-5)."""
    X = np.asarray(X, dtype=float)
    col = {name: X[:, i] for name, i in _COL.items()}
    logit = np.full(X.shape[0], BASE_LOGIT)
    logit += DONE_PER * np.clip(col["times_done"], 0, rf.COUNT_CAP)
    logit += SKIPPED_PER * np.clip(col["times_skipped"], 0, rf.COUNT_CAP)
    logit += SWAPPED_PER * np.clip(col["times_swapped"], 0, rf.COUNT_CAP)
    days = np.clip(np.floor(col["days_since_trained"]), 0, rf.DAYS_CAP).astype(int)
    penalty = np.zeros(X.shape[0])
    for d, p in enumerate(REST_PENALTY):
        penalty[days == d] = p
    logit += penalty
    logit += PICKED_BONUS * (col["picked_equipment"] > 0)
    logit += LOCATION_BONUS * (col["location_fit"] > 0)
    return logit


def _choice(rng, table, size):
    keys = list(table)
    index = rng.choice(len(keys), size=size, p=list(table.values()))
    return [keys[i] for i in index]


def simulate(rows: int = ROWS, seed: int = SEED) -> SimulatedRanking:
    if rows % CANDIDATES_PER_TRAINEE:
        raise ValueError("rows must be a multiple of {}".format(CANDIDATES_PER_TRAINEE))
    rng = np.random.default_rng(seed)
    trainees = rows // CANDIDATES_PER_TRAINEE
    trainee = np.repeat(np.arange(trainees), CANDIDATES_PER_TRAINEE)
    coverage = np.repeat(rng.random(trainees) < COVERAGE_SHARE, CANDIDATES_PER_TRAINEE)

    goals = _choice(rng, GOAL_P, trainees)
    levels = _choice(rng, LEVEL_P, trainees)
    locations = _choice(rng, LOCATION_P, trainees)
    splits = _choice(rng, SPLIT_P, trainees)
    caution = rng.random(trainees) < CAUTION_P
    cover_trainee = coverage[::CANDIDATES_PER_TRAINEE]

    situations = []
    drawn_fit = []   # location fit is drawn directly, not derived from a name
    for t in range(trainees):
        gentle = levels[t] != "intermediate" or bool(caution[t])
        session = 60 if goals[t] in LONG_SESSION_GOALS and not gentle else 45
        prefers_location = locations[t] in ("commercial_gym", "home_gym", "other")
        for _ in range(CANDIDATES_PER_TRAINEE):
            if cover_trainee[t]:
                first = rng.random() < 0.5
                friendly = True if gentle else rng.random() < 0.5
                picked = rng.random() < 0.5
                fit = prefers_location and rng.random() < 0.5
                never = rng.random() < 1 / (rf.DAYS_CAP + 1)
                days = None if never else int(rng.integers(0, rf.DAYS_CAP))
                done, skipped, swapped = (int(v) for v in rng.integers(0, rf.COUNT_CAP + 1, 3))
            else:
                if gentle:
                    first = rng.random() < GENTLE_FIRST_P
                    friendly = True
                else:
                    first = rng.random() < OPEN_FIRST_P
                    friendly = rng.random() < (OPEN_FRIENDLY_GIVEN_FIRST_P if first
                                               else OPEN_FRIENDLY_GIVEN_ALTERNATIVE_P)
                picked = rng.random() < PICKED_P
                fit = prefers_location and rng.random() < LOCATION_FIT_P
                never = rng.random() < NEVER_TRAINED_P
                days = None if never else int(rng.integers(0, rf.DAYS_CAP))
                done = int(min(rng.poisson(DONE_MEAN), rf.COUNT_CAP))
                skipped = int(min(rng.poisson(SKIPPED_MEAN), rf.COUNT_CAP))
                swapped = int(min(rng.poisson(SWAPPED_MEAN), rf.COUNT_CAP))
            situations.append({
                "mainGoal": goals[t], "fitnessLevel": levels[t],
                "trainingLocation": locations[t], "sessionLengthMin": session,
                "splitStyle": splits[t], "healthCaution": bool(caution[t]),
                "mark": "first" if first else "alternative",
                "beginnerFriendly": friendly, "pickedEquipment": picked,
                "equipmentName": None,
                "daysSinceTrained": days,
                "timesDone": done, "timesSkipped": skipped, "timesSwapped": swapped,
            })
            drawn_fit.append(1.0 if fit else 0.0)

    X = np.array([rf.encode(s) for s in situations], dtype=float)
    # encode() derives location_fit from equipmentName (None here, so 0); the
    # simulation draws it instead.
    X[:, _COL["location_fit"]] = np.array(drawn_fit)
    logit = expected_logit(X) + rng.normal(0.0, NOISE_SD, size=rows)
    probability = np.clip(1.0 / (1.0 + np.exp(-logit)), P_MIN, P_MAX)
    y = (rng.random(rows) < probability).astype(int)
    return SimulatedRanking(X=X, y=y, probability=probability, coverage=coverage,
                            trainee=trainee, seed=seed, rows=rows)
