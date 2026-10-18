"""The training CLI: python -m app.train_risk."""
import csv
import json
from pathlib import Path

import pytest

from app import risk_data, risk_model, train_risk
from app.config import Settings

COMMITTED_REPORT = Path(__file__).resolve().parents[1] / "reports" / "injury_risk_cv.json"


def run(tmp_path, *extra):
    report = tmp_path / "report.json"
    code = train_risk.main([
        "--model-dir", str(tmp_path / "models"), "--report", str(report),
        "--rows", "4000", *extra,
    ])
    assert code == 0
    return json.loads(report.read_text())


def settings_for(model_dir):
    return Settings(db_host="h", db_port=1, db_user="u", db_password="p",
                    db_name="n", model_dir=str(model_dir))


def test_it_writes_a_model_the_service_loads(tmp_path):
    run(tmp_path)
    path = tmp_path / "models" / risk_model.MODEL_FILENAME
    assert path.is_file()
    assert path.stat().st_size < 2 * 1024 * 1024
    loaded = risk_model.RiskModel.load(settings_for(tmp_path / "models"))
    assert loaded.status == "loaded"
    assert loaded.version == risk_model.MODEL_VERSION


def test_the_report_says_plainly_what_the_model_was_trained_on(tmp_path):
    report = run(tmp_path)
    assert report["modelVersion"] == "risk-rf-sim-1"
    assert report["data"]["kind"] == "simulated"
    assert report["data"]["seed"] == risk_data.SEED
    assert report["data"]["simulatedRows"] == 4000
    assert report["data"]["realRows"] == 0
    assert report["features"] == list(risk_data.FEATURES)
    import sklearn
    assert report["sklearnVersion"] == sklearn.__version__
    statement = report["statement"].lower()
    assert "simulated" in statement
    assert "not" in statement and "real" in statement
    for metric in ("rocAuc", "brier", "levelAgreementWithRules", "rulesRocAuc"):
        assert "mean" in report["crossValidation"][metric]
    assert report["crossValidation"]["k"] == 5


def test_the_report_records_the_simulation_it_was_built_from(tmp_path):
    simulation = run(tmp_path)["simulation"]
    assert simulation["loadPerPct"] == risk_data.LOAD_PER_PCT
    assert simulation["coverageShare"] == risk_data.COVERAGE_SHARE
    assert "Tsilimigkras" in " ".join(simulation["sources"])
    assert "Xu" in " ".join(simulation["sources"])


def test_the_same_arguments_give_the_same_report(tmp_path):
    first = run(tmp_path / "a")
    second = run(tmp_path / "b")
    assert first == second


def write_real(path, rows, header=None):
    header = header or list(risk_data.FEATURES) + ["injured"]
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def test_real_rows_are_mixed_in_and_counted(tmp_path):
    real = tmp_path / "real.csv"
    write_real(real, [[1, 1, 1, 1, 20.5, 0, 0, 0], [3, 2.6667, 2, 3, 110, 2, 3, 1]] * 30)
    report = run(tmp_path, "--real", str(real))
    assert report["data"]["realRows"] == 60
    assert report["crossValidation"]["rows"] == 4060
    assert report["data"]["kind"] == "simulated+real"


@pytest.mark.parametrize("rows, header, message", [
    ([[1, 1, 1, 1, 20, 0, 0]], list(risk_data.FEATURES), "injured"),
    ([[1, 1, 1, 1, 20, 0, 0, 2]], None, "injured"),
    ([[1, 1, 1, 1, 500, 0, 0, 1]], None, "load_pct"),
    ([[1, 1, 1, "x", 20, 0, 0, 1]], None, "stress"),
    ([], None, "no rows"),
])
def test_a_bad_real_csv_is_refused_with_the_reason(tmp_path, rows, header, message):
    real = tmp_path / "real.csv"
    write_real(real, rows, header)
    with pytest.raises(SystemExit) as excinfo:
        train_risk.main(["--model-dir", str(tmp_path / "m"),
                         "--report", str(tmp_path / "r.json"),
                         "--rows", "1000", "--real", str(real)])
    assert message in str(excinfo.value)
    assert not (tmp_path / "m" / risk_model.MODEL_FILENAME).exists()


def rounded(value, places=3):
    """Every float in a report rounded, so a library upgrade that moves a
    metric in its fourth decimal is not mistaken for a stale report."""
    if isinstance(value, float):
        return round(value, places)
    if isinstance(value, list):
        return [rounded(v, places) for v in value]
    if isinstance(value, dict):
        return {k: rounded(v, places) for k, v in value.items()}
    return value


def test_the_committed_report_is_what_the_defaults_produce(tmp_path):
    # Guards against the committed report going stale when the simulation or
    # the forest changes: regenerate it with `python -m app.train_risk`.
    committed = json.loads(COMMITTED_REPORT.read_text())
    if committed["data"]["kind"] != "simulated":
        pytest.skip("the committed report includes real rows, which this "
                    "checkout cannot reproduce from the defaults")
    report = tmp_path / "report.json"
    assert train_risk.main(["--model-dir", str(tmp_path), "--report", str(report)]) == 0
    assert rounded(committed) == rounded(json.loads(report.read_text()))


def test_the_report_states_the_models_limitations(tmp_path):
    report = run(tmp_path)
    limitations = " ".join(report["limitations"]).lower()
    # Its coefficients are not measured sizes ...
    assert "judgement" in limitations and "not sizes measured" in limitations
    # ... and the forest learns them only coarsely.
    assert "moderate from severe recent pain" in limitations
    assert "two from three past injuries" in limitations
    assert "rare combinations" in limitations and "floor" in limitations
    assert "single" in limitations and "above" in limitations
    # A calm day is not scored 0, so Readiness on one is below 100.
    assert "calm day" in limitations and "100" in limitations


def test_the_comparison_claims_no_more_than_the_model_does(tmp_path):
    comparison = run(tmp_path)["comparisonWithRules"]
    assert "as the cited literature weighs them" not in comparison
    assert "claims no more accuracy than the rules" in comparison
    assert "not sizes measured" in comparison
    assert "coarsely" in comparison
    assert "retrainable" in comparison


def test_the_report_shows_the_model_beside_its_simulation_on_named_days(tmp_path):
    probes = run(tmp_path)["probes"]
    days = [probe["day"] for probe in probes]
    for day in ("a calm day", "one past injury alone",
                "two past injuries alone", "three past injuries alone",
                "moderate recent pain alone", "severe recent pain alone",
                "the worst answers, three injuries and severe pain"):
        assert day in days
    for probe in probes:
        assert set(probe) == {"day", "model", "simulation", "rules", "final"}
        assert probe["final"] == max(probe["model"], probe["rules"])
        assert 0.0 <= probe["model"] <= 100.0


def test_the_probes_are_scored_by_the_saved_model(tmp_path):
    # The same classifier the service would load, read through the service's
    # own feature path, so the numbers are what a user would see.
    report = run(tmp_path)
    loaded = risk_model.RiskModel.load(settings_for(tmp_path / "models"))
    from app.schemas import InjuryRiskRequest
    for probe, body in zip(report["probes"], train_risk.PROBES):
        assert probe["day"] == body[0]
        assert probe["model"] == loaded.score(InjuryRiskRequest.model_validate(body[1]))


def test_a_model_trained_with_real_rows_is_versioned_apart(tmp_path):
    real = tmp_path / "real.csv"
    write_real(real, [[1, 1, 1, 1, 20.5, 0, 0, 0], [3, 2.6667, 2, 3, 110, 2, 3, 1]] * 30)
    report = run(tmp_path, "--real", str(real))
    assert report["modelVersion"] == "risk-rf-sim+real-1"
    loaded = risk_model.RiskModel.load(settings_for(tmp_path / "models"))
    assert loaded.version == "risk-rf-sim+real-1"
    # Fits the server's model_version VARCHAR(40).
    assert len(loaded.version) <= 40


def test_a_simulated_only_model_keeps_the_plain_version(tmp_path):
    assert run(tmp_path)["modelVersion"] == risk_model.MODEL_VERSION


def test_with_real_rows_the_comparison_is_made_on_the_same_rows(tmp_path):
    real = tmp_path / "real.csv"
    write_real(real, [[1, 1, 1, 1, 20.5, 0, 0, 0], [3, 2.6667, 2, 3, 110, 2, 3, 1]] * 30)
    report = run(tmp_path, "--real", str(real))
    cv = report["crossValidation"]
    # The rules can only be scored on simulated rows (real rows keep no raw
    # answers), so the model is also scored on exactly those rows.
    assert "mean" in cv["rocAucWhereRulesKnown"]
    comparison = report["comparisonWithRules"]
    assert "{:.3f}".format(cv["rocAucWhereRulesKnown"]["mean"]) in comparison
    assert "real" in comparison


def test_real_rows_with_a_user_id_keep_each_user_in_one_fold(tmp_path):
    real = tmp_path / "real.csv"
    header = list(risk_data.FEATURES) + ["injured", "user_id"]
    rows = []
    for user in range(20):
        rows.append([1, 1, 1, 1, 20.5, 0, 0, 0, "u{}".format(user)])
        rows.append([3, 2.6667, 2, 3, 110, 2, 3, 1, "u{}".format(user)])
    write_real(real, rows, header)
    report = run(tmp_path, "--real", str(real))
    assert report["crossValidation"]["method"] == "StratifiedGroupKFold"
    assert report["data"]["realUsers"] == 20


def test_real_rows_without_a_user_id_use_a_plain_stratified_split(tmp_path):
    real = tmp_path / "real.csv"
    write_real(real, [[1, 1, 1, 1, 20.5, 0, 0, 0], [3, 2.6667, 2, 3, 110, 2, 3, 1]] * 30)
    report = run(tmp_path, "--real", str(real))
    assert report["crossValidation"]["method"] == "StratifiedKFold"
    assert report["data"]["realUsers"] is None


def test_an_empty_user_id_is_refused(tmp_path):
    real = tmp_path / "real.csv"
    header = list(risk_data.FEATURES) + ["injured", "user_id"]
    write_real(real, [[1, 1, 1, 1, 20.5, 0, 0, 0, ""]], header)
    with pytest.raises(SystemExit) as excinfo:
        train_risk.main(["--model-dir", str(tmp_path / "m"),
                         "--report", str(tmp_path / "r.json"),
                         "--rows", "1000", "--real", str(real)])
    assert "user_id" in str(excinfo.value)


def test_requirements_need_a_scikit_learn_with_monotonic_forests():
    # RandomForestClassifier takes monotonic_cst from scikit-learn 1.4; below
    # that, training raises and the service silently serves the rules alone.
    import re

    requirements = (COMMITTED_REPORT.parents[1] / "requirements.txt").read_text()
    match = re.search(r"^scikit-learn>=(\d+)\.(\d+)", requirements, re.M)
    assert match and (int(match.group(1)), int(match.group(2))) >= (1, 4)
