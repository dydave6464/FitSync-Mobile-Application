"""Training-load and recovery -> a conservative injury-risk estimate.

This endpoint has no caller yet: there is no morning check-in route, so nothing
invokes it and no data exists to tune it. It returns the same floor the Node
stub returns (low, 0) when given nothing, so switching ML_MODE changes nothing
observable today. See the design, section 13.

This is guidance bounded by self-reported input, not a clinical assessment.
"""
from app.schemas import InjuryRiskRequest, InjuryRiskResponse

# Each scale runs worst -> best; the value is how much it adds to the score.
SLEEP = {"poor": 15.0, "fair": 8.0, "good": 2.0, "excellent": 0.0}
SORENESS = {"severe": 20.0, "moderate": 10.0, "mild": 4.0, "none": 0.0}
ENERGY = {"very_low": 12.0, "low": 7.0, "moderate": 2.0, "high": 0.0}
STRESS = {"high": 10.0, "moderate": 5.0, "low": 2.0, "very_low": 0.0}

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


def estimate(payload: InjuryRiskRequest) -> InjuryRiskResponse:
    score = max(payload.load, 0.0) / 2.0
    if payload.checkins:
        penalties = [_recovery_penalty(c) for c in payload.checkins]
        score += sum(penalties) / len(penalties)

    # training_load_score is DECIMAL(5,2): outside [0, 100] MySQL would reject
    # or truncate it, and more than two decimals would round silently.
    score = round(min(max(score, SCORE_MIN), SCORE_MAX), 2)

    if score >= HIGH_AT:
        level = "high"
    elif score >= MODERATE_AT:
        level = "moderate"
    else:
        level = "low"

    return InjuryRiskResponse(riskLevel=level, trainingLoadScore=score)
