"""The rules' injury terms, drivers and loadPct.

test_risk.py is deliberately left as it was: it pins today's scores for a
request with no injuries and no pain. These tests cover what the injury terms
add on top, and the explanation the response now carries.
"""
import pytest

from app.risk import estimate
from app.schemas import InjuryRiskRequest

GOOD_DAY = {"sleepQuality": "excellent", "muscleSoreness": "none",
            "energy": "high", "stress": "very_low"}


def score(**fields):
    return estimate(InjuryRiskRequest(**fields)).trainingLoadScore


def injuries(n):
    return [{"injuryId": i + 1, "regionGroup": "knee"} for i in range(n)]


def test_no_injuries_and_no_pain_score_exactly_as_before():
    # The server's load calibration test assumes load / 2 is the whole score
    # for a rested user; the injury terms must add nothing when they are empty.
    assert score(load=35.0) == 17.5
    assert score(load=35.0, injuryHistory=[], recentPain=None) == 17.5
    assert score(load=35.0, recentPain="none") == 17.5


@pytest.mark.parametrize("count, added", [(1, 5.0), (2, 10.0), (3, 10.0), (6, 10.0)])
def test_each_reported_injury_adds_five_capped_at_ten(count, added):
    assert score(load=20.0, injuryHistory=injuries(count)) == 10.0 + added


@pytest.mark.parametrize("pain, added", [
    ("none", 0.0), ("mild", 5.0), ("moderate", 10.0), ("severe", 20.0),
])
def test_recent_pain_adds_by_severity(pain, added):
    assert score(load=20.0, recentPain=pain) == 10.0 + added


def test_an_unrecognised_pain_value_adds_nothing_rather_than_failing():
    # Permissive like the check-in answers: a value this service does not know
    # is not evidence of pain, and refusing would cost the user an estimate.
    assert score(load=20.0, recentPain="banana") == 10.0


def test_the_injury_terms_still_respect_the_column_range():
    result = score(load=130.0, injuryHistory=injuries(3), recentPain="severe",
                   checkins=[{"sleepQuality": "poor", "muscleSoreness": "severe",
                              "energy": "very_low", "stress": "high"}])
    assert result == 100.0


def test_injuries_and_pain_can_move_the_level():
    assert estimate(InjuryRiskRequest(load=60.0)).riskLevel == "low"
    assert estimate(InjuryRiskRequest(
        load=60.0, injuryHistory=injuries(1), recentPain="mild",
    )).riskLevel == "moderate"


def test_the_old_request_body_still_validates():
    payload = InjuryRiskRequest.model_validate(
        {"checkins": [], "load": 35.0, "injuryHistory": []}
    )
    result = estimate(payload)
    assert result.trainingLoadScore == 17.5
    assert result.riskLevel == "low"


# --- loadPct, source and drivers -------------------------------------------


def test_load_pct_echoes_the_load_index():
    assert estimate(InjuryRiskRequest(load=35.0)).loadPct == 35.0


def test_the_rules_alone_report_source_rules_and_no_model_version():
    result = estimate(InjuryRiskRequest(load=35.0))
    assert result.source == "rules"
    assert result.modelVersion is None


def test_nothing_standing_out_gives_an_empty_driver_list():
    result = estimate(InjuryRiskRequest(load=0.0, checkins=[GOOD_DAY]))
    assert result.drivers == []


def test_drivers_are_the_top_three_positive_contributors_most_first():
    result = estimate(InjuryRiskRequest(
        load=35.0,                                  # 17.5 points
        checkins=[{"sleepQuality": "poor",          # 15
                   "muscleSoreness": "mild",        # 4
                   "energy": "high",                # 0
                   "stress": "low"}],               # 2
        injuryHistory=injuries(2),                  # 10
        recentPain="moderate",                      # 10
    ))
    drivers = [d.model_dump() for d in result.drivers]
    assert drivers == [
        {"key": "load", "value": 35.0},
        {"key": "sleep", "value": "poor"},
        # injury_history and recent_pain tie on 10 points; the tie breaks the
        # same way every time so the app's sentence does not flicker.
        {"key": "injury_history", "value": 2},
    ]


def test_a_check_in_driver_names_the_worst_answer_in_the_window():
    # The points are averaged across the window, but the sentence the app
    # builds ("you slept poorly") names the worst night, which is what the
    # user remembers.
    result = estimate(InjuryRiskRequest(load=0.0, checkins=[
        dict(GOOD_DAY, sleepQuality="fair"),
        dict(GOOD_DAY, sleepQuality="poor"),
        dict(GOOD_DAY, sleepQuality="good"),
    ]))
    assert [d.model_dump() for d in result.drivers] == [
        {"key": "sleep", "value": "poor"},
    ]


def test_driver_values_keep_their_wire_types():
    result = estimate(InjuryRiskRequest(
        load=12.5, injuryHistory=injuries(1), recentPain="severe",
    ))
    values = {d.key: d.value for d in result.drivers}
    assert values["recent_pain"] == "severe"
    assert values["injury_history"] == 1 and isinstance(values["injury_history"], int)
    assert values["load"] == 12.5 and isinstance(values["load"], float)


def test_every_driver_key_is_one_the_contract_names():
    result = estimate(InjuryRiskRequest(
        load=90.0,
        checkins=[{"sleepQuality": "poor", "muscleSoreness": "severe",
                   "energy": "very_low", "stress": "high"}],
        injuryHistory=injuries(3), recentPain="severe",
    ))
    assert len(result.drivers) == 3
    assert {d.key for d in result.drivers} <= {
        "load", "sleep", "soreness", "energy", "stress",
        "injury_history", "recent_pain",
    }
