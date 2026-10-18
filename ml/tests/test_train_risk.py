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


def test_the_committed_report_is_what_the_defaults_produce(tmp_path):
    # Guards against the committed report going stale when the simulation or
    # the forest changes: regenerate it with `python -m app.train_risk`.
    report = tmp_path / "report.json"
    assert train_risk.main(["--model-dir", str(tmp_path), "--report", str(report)]) == 0
    assert json.loads(COMMITTED_REPORT.read_text()) == json.loads(report.read_text())
