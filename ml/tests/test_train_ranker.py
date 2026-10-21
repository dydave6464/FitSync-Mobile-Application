import csv
import json
import os

import pytest

from app import ranker_data as rd
from app import ranker_features as rf
from app import train_ranker as tr

REPORT = os.path.join(os.path.dirname(__file__), "..", "reports", "plan_ranker_cv.json")

ROW = {
    "user_id": "7", "event_date": "2026-10-20", "kind": "prescribed",
    "main_goal": "build_muscle", "fitness_level": "intermediate",
    "training_location": "home_gym", "session_length_min": "60",
    "split_style": "push_pull_legs", "health_caution": "0",
    "exercise_id": "412", "mark": "first", "beginner_friendly": "1",
    "equipment_name": "dumbbell", "picked_equipment": "1",
    "muscle_group": "quads", "days_since_trained": "", "times_done": "2",
    "times_skipped": "0", "times_swapped": "1", "done": "1",
}


def write_csv(path, rows, columns=tr.CSV_COLUMNS):
    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)


def test_csv_columns_are_the_agreed_contract():
    assert tr.CSV_COLUMNS == (
        "user_id", "event_date", "kind", "main_goal", "fitness_level",
        "training_location", "session_length_min", "split_style",
        "health_caution", "exercise_id", "mark", "beginner_friendly",
        "equipment_name", "picked_equipment", "muscle_group",
        "days_since_trained", "times_done", "times_skipped", "times_swapped",
        "done",
    )


def test_a_real_row_encodes_like_a_live_candidate(tmp_path):
    path = tmp_path / "real.csv"
    write_csv(path, [ROW, dict(ROW, user_id="8", done="0", days_since_trained="3")])
    X, y, groups = tr.load_real(str(path))
    assert X.shape == (2, len(rf.FEATURES))
    assert list(y) == [1, 0]
    assert list(groups) == ["7", "8"]
    first = dict(zip(rf.FEATURES, X[0]))
    assert first["days_since_trained"] == rf.DAYS_CAP     # empty = never
    assert first["location_fit"] == 1                     # dumbbell at home
    assert first["times_swapped"] == 1


@pytest.mark.parametrize("column,value", [
    ("done", "2"), ("kind", "maybe"), ("times_done", "x"), ("user_id", ""),
])
def test_bad_rows_are_refused_with_the_line(tmp_path, column, value):
    path = tmp_path / "bad.csv"
    write_csv(path, [ROW, dict(ROW, **{column: value})])
    with pytest.raises(SystemExit) as err:
        tr.load_real(str(path))
    assert "line 3" in str(err.value)


def test_a_missing_column_is_refused(tmp_path):
    path = tmp_path / "short.csv"
    columns = [c for c in tr.CSV_COLUMNS if c != "mark"]
    write_csv(path, [{k: v for k, v in ROW.items() if k != "mark"}], columns)
    with pytest.raises(SystemExit) as err:
        tr.load_real(str(path))
    assert "mark" in str(err.value)


def test_the_cli_writes_a_model_and_a_report(tmp_path):
    report = tmp_path / "r.json"
    code = tr.main(["--model-dir", str(tmp_path), "--report", str(report),
                    "--rows", "3000"])
    assert code == 0
    assert (tmp_path / "plan_ranker.joblib").is_file()
    data = json.loads(report.read_text())
    assert data["modelVersion"] == "ranker-rf-sim-1"
    assert data["statement"] == tr.STATEMENT
    assert data["features"] == list(rf.FEATURES)
    assert data["probes"] and all("order" in probe for probe in data["probes"])
    assert 0.0 <= data["topPickChangedShare"] <= 1.0


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
    # Guards against the committed report going stale when the simulation,
    # the forest or the ordering rule changes: regenerate it with
    # `python -m app.train_ranker`.
    with open(REPORT) as handle:
        committed = json.load(handle)
    if committed["data"]["kind"] != "simulated" or committed["data"]["realRows"]:
        pytest.skip("the committed report includes real rows, which this "
                    "checkout cannot reproduce from the defaults")
    assert committed["data"]["seed"] == rd.SEED
    assert committed["data"]["simulatedRows"] == rd.ROWS
    report = tmp_path / "r.json"
    assert tr.main(["--model-dir", str(tmp_path), "--report", str(report)]) == 0
    assert rounded(committed) == rounded(json.loads(report.read_text()))


def test_the_report_describes_the_ordering_as_bands_not_a_gap():
    # reorder() compares floor(score / 0.05): two scores 0.2 points apart can
    # land in different bands and reorder, while 4.8 points apart in one band
    # do not. The report must not promise a minimum gap.
    text = " ".join(tr.LIMITATIONS).lower()
    assert "band" in text
    assert "clear step" not in text
