from app.risk import estimate
from app.schemas import InjuryRiskRequest


def test_no_data_reports_the_conservative_floor():
    # Matches the stub exactly, so flipping ML_MODE changes nothing observable
    # until the morning check-in route exists. Section 13.
    result = estimate(InjuryRiskRequest())
    assert result.riskLevel == "low"
    assert result.trainingLoadScore == 0.0


def test_a_high_load_with_poor_recovery_raises_the_level():
    result = estimate(InjuryRiskRequest(
        load=90.0,
        checkins=[{"sleepQuality": "poor", "muscleSoreness": "severe",
                   "energy": "very_low", "stress": "high"}],
    ))
    assert result.riskLevel in ("moderate", "high")
    assert result.trainingLoadScore > 0


def test_the_score_is_clamped_to_the_column_range():
    # training_load_score is DECIMAL(5,2), so anything outside [0, 100] or with
    # more than two decimals would be truncated or rejected by MySQL.
    result = estimate(InjuryRiskRequest(load=10_000.0))
    assert 0.0 <= result.trainingLoadScore <= 100.0
    assert round(result.trainingLoadScore, 2) == result.trainingLoadScore

    negative = estimate(InjuryRiskRequest(load=-50.0))
    assert negative.trainingLoadScore >= 0.0


def test_the_level_is_always_one_of_the_three_enum_values():
    for load in (0.0, 25.0, 55.0, 85.0, 100.0):
        assert estimate(InjuryRiskRequest(load=load)).riskLevel in (
            "low", "moderate", "high"
        )


def test_good_recovery_lowers_the_level_at_the_same_load():
    load = 70.0
    poor = estimate(InjuryRiskRequest(
        load=load,
        checkins=[{"sleepQuality": "poor", "muscleSoreness": "severe",
                   "energy": "very_low", "stress": "high"}],
    ))
    good = estimate(InjuryRiskRequest(
        load=load,
        checkins=[{"sleepQuality": "excellent", "muscleSoreness": "none",
                   "energy": "high", "stress": "very_low"}],
    ))
    assert good.trainingLoadScore < poor.trainingLoadScore


def test_an_unrecognised_checkin_value_does_not_raise():
    result = estimate(InjuryRiskRequest(
        load=50.0, checkins=[{"sleepQuality": "banana"}]
    ))
    assert result.riskLevel in ("low", "moderate", "high")
