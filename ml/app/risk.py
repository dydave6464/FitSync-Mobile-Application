"""Training load, recovery and past injuries -> the rule-based injury-risk score.

Called by the Node server's POST /api/v1/recovery/checkin, which computes the
training-load index (see src/db/training-load.js) and sends a short window of
recent check-ins -- short deliberately, because the recovery penalty below is
averaged across every check-in in it, so the width of that window is how much
this morning's answers are worth.

These rules are the safety floor under the scikit-learn model in
app/risk_model.py: the final score is max(model score, rules score), so a model
can raise an estimate but never lower it below what these rules say. That model
is trained on simulated data built from published injury risk factors (see
app/risk_data.py), not on real user outcomes; it is retrained on real check-in
outcomes as they accumulate. The rules also supply the response's drivers,
because their points are explainable whichever side decided the score.

This is guidance bounded by self-reported input, not a clinical assessment.
"""
import math
from typing import Dict, List, Optional

from app.schemas import InjuryRiskRequest, InjuryRiskResponse, RiskDriver

# Each scale runs worst -> best; the value is how much it adds to the score.
SLEEP = {"poor": 15.0, "fair": 8.0, "good": 2.0, "excellent": 0.0}
SORENESS = {"severe": 20.0, "moderate": 10.0, "mild": 4.0, "none": 0.0}
ENERGY = {"very_low": 12.0, "low": 7.0, "moderate": 2.0, "high": 0.0}
STRESS = {"high": 10.0, "moderate": 5.0, "low": 2.0, "very_low": 0.0}

# Past injuries and recent pain, added to the formula above without changing
# any of it: with no injuries and no pain the score is exactly what it was, so
# the server's load calibration test stays valid. Prior injury is among the
# strongest predictors in the literature the manuscript cites (Xu et al. 2025),
# but a profile entry is old news, so each one counts for less than a single
# bad night and two of them are the most it can add.
INJURY_EACH = 5.0
INJURY_CAP = 10.0
# Pain reported after a session in the last 14 days is current, so severe pain
# outweighs a full injury history.
PAIN = {"severe": 20.0, "moderate": 10.0, "mild": 5.0, "none": 0.0}

# Which check-in answer feeds which driver key, and the table that scores it.
CHECKIN_FIELDS = (
    ("sleep", "sleepQuality", SLEEP),
    ("soreness", "muscleSoreness", SORENESS),
    ("energy", "energy", ENERGY),
    ("stress", "stress", STRESS),
)

# Ties between drivers break in this order, so the same inputs always produce
# the same "Why this level" sentence.
DRIVER_ORDER = (
    "load", "injury_history", "recent_pain", "sleep", "soreness", "energy", "stress",
)
MAX_DRIVERS = 3

MODERATE_AT = 40.0
HIGH_AT = 70.0

SCORE_MIN = 0.0
SCORE_MAX = 100.0


def _recovery_penalty(checkin) -> float:
    if not isinstance(checkin, dict):
        return 0.0
    return (
        SLEEP.get(checkin.get("sleepQuality"), 0.0)
        + SORENESS.get(checkin.get("muscleSoreness"), 0.0)
        + ENERGY.get(checkin.get("energy"), 0.0)
        + STRESS.get(checkin.get("stress"), 0.0)
    )


def injury_points(payload: InjuryRiskRequest) -> float:
    return min(INJURY_EACH * len(payload.injuryHistory), INJURY_CAP)


def pain_points(payload: InjuryRiskRequest) -> float:
    return PAIN.get(payload.recentPain, 0.0)


def level_for(score: float) -> str:
    if score >= HIGH_AT:
        return "high"
    if score >= MODERATE_AT:
        return "moderate"
    return "low"


def _worst_answer(checkins, field: str, table: Dict[str, float]) -> Optional[str]:
    """The answer in the window that scores the most points, if any is known."""
    known = [
        c.get(field) for c in checkins
        if isinstance(c, dict) and c.get(field) in table
    ]
    return max(known, key=lambda answer: table[answer]) if known else None


def drivers(payload: InjuryRiskRequest) -> List[RiskDriver]:
    """The inputs that raised the rules' score, most points first.

    Ranked by the rules' own points even when the model decided the final
    score: the rules' points are the explanation that can be given in a
    sentence, and an input that added nothing is never named. The check-in
    points are averaged over the window, exactly as in the score, but the value
    reported is the worst answer, which is the one the user remembers.
    """
    candidates = []
    load = max(payload.load, 0.0)
    if load / 2.0 > 0:
        candidates.append(("load", load / 2.0, round(load, 2)))
    if payload.checkins:
        for key, field, table in CHECKIN_FIELDS:
            points = sum(
                table.get(c.get(field), 0.0) if isinstance(c, dict) else 0.0
                for c in payload.checkins
            ) / len(payload.checkins)
            if points > 0:
                candidates.append(
                    (key, points, _worst_answer(payload.checkins, field, table))
                )
    if injury_points(payload) > 0:
        candidates.append(
            ("injury_history", injury_points(payload), len(payload.injuryHistory))
        )
    if pain_points(payload) > 0:
        candidates.append(("recent_pain", pain_points(payload), payload.recentPain))

    candidates.sort(key=lambda c: (-c[1], DRIVER_ORDER.index(c[0])))
    return [RiskDriver(key=key, value=value)
            for key, _, value in candidates[:MAX_DRIVERS]]


def rules_score(payload: InjuryRiskRequest) -> float:
    if not math.isfinite(payload.load):
        # Checked on the raw load, not the derived score: max(-inf, 0.0) is a
        # well-defined comparison that legitimately evaluates to 0.0, so -inf
        # would otherwise be coerced to a finite score before a later
        # isfinite(score) check ever saw it -- only NaN and +inf survive that
        # form of the guard. NaN defeats min/max entirely (every comparison
        # with it is False) and Infinity would otherwise clamp silently.
        # Neither is a risk estimate, so refuse rather than invent one -- the
        # schema rejects these, and this guards a caller that bypasses it.
        raise ValueError("training load must be a finite number")

    score = max(payload.load, 0.0) / 2.0
    if payload.checkins:
        penalties = [_recovery_penalty(c) for c in payload.checkins]
        score += sum(penalties) / len(penalties)
    score += injury_points(payload) + pain_points(payload)

    # training_load_score is DECIMAL(5,2): outside [0, 100] MySQL would reject
    # or truncate it, and more than two decimals would round silently.
    return round(min(max(score, SCORE_MIN), SCORE_MAX), 2)


def estimate(payload: InjuryRiskRequest) -> InjuryRiskResponse:
    """The rules alone: the floor, and the whole answer when no model loads."""
    score = rules_score(payload)
    return InjuryRiskResponse(
        riskLevel=level_for(score),
        trainingLoadScore=score,
        source="rules",
        modelVersion=None,
        loadPct=round(max(payload.load, 0.0), 2),
        drivers=drivers(payload),
    )
