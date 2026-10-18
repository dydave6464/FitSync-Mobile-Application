"""Train the injury-risk model and write its cross-validation report.

    cd ml
    .venv/bin/python -m app.train_risk                 # simulated data only
    .venv/bin/python -m app.train_risk --real real.csv # mix in real outcomes

Writes models/injury_risk.joblib (git-ignored; FITSYNC_MODEL_DIR or --model-dir
moves it) and reports/injury_risk_cv.json (committed). The running service has
no auto-reload: restart it to pick up a new model file.

The model is trained on simulated user-days (app/risk_data.py). --real mixes
in real labelled rows for when they exist; nothing in the server exports them
yet. The CSV has a header row and these columns, in any order:

    sleep, soreness, energy, stress  3-day mean of the answer's position on
                                     its scale, 0 = best ... 3 = worst
                                     (sleep: excellent, good, fair, poor;
                                     soreness: none, mild, moderate, severe;
                                     energy: high, moderate, low, very_low;
                                     stress: very_low, low, moderate, high)
    load_pct                         training-load index, 0-130
    injury_count                     reported injuries; above 3 counts as 3
    recent_pain                      worst pain in the last 14 days, 0-3
                                     (none, mild, moderate, severe)
    injured                          1 if injured within the week, else 0

Real rows are always scored in cross-validation, and they are kept apart from
the simulation in the report's row counts.
"""
import argparse
import csv
import json
import os
import sys
from typing import List, Optional, Tuple

import numpy as np

from app import risk_data, risk_model

DEFAULT_REPORT = os.path.join("reports", "injury_risk_cv.json")
LABEL = "injured"

# Allowed range per CSV column. injury_count has no upper bound here because
# the service caps it at 3 (risk_model.features_for) and so does this loader.
RANGES = {
    "sleep": (0.0, 3.0),
    "soreness": (0.0, 3.0),
    "energy": (0.0, 3.0),
    "stress": (0.0, 3.0),
    "load_pct": (0.0, risk_data.LOAD_MAX),
    "injury_count": (0.0, float("inf")),
    "recent_pain": (0.0, 3.0),
}

STATEMENT = (
    "This model is trained on simulated data built from published injury risk "
    "factors (Tsilimigkras et al. 2024; Xu et al. 2025), not on real user "
    "outcomes, and it is retrained on real check-in outcomes as they "
    "accumulate. The cross-validation metrics measure how well it learned "
    "that simulation; they say nothing about accuracy on real injuries, and "
    "the model is not clinically validated. The rule-based score stays as a "
    "safety floor: the final score is never lower than the rules' score."
)


def load_real(path: str) -> Tuple[np.ndarray, np.ndarray]:
    """Real labelled rows from a CSV, validated, in FEATURES order."""
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in list(risk_data.FEATURES) + [LABEL]
                   if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit("{}: missing column(s): {}".format(path, ", ".join(missing)))
        X: List[List[float]] = []
        y: List[int] = []
        for line, row in enumerate(reader, start=2):
            values = []
            for name in risk_data.FEATURES:
                low, high = RANGES[name]
                try:
                    value = float(row[name])
                except (TypeError, ValueError):
                    raise SystemExit("{} line {}: {} is not a number: {!r}".format(
                        path, line, name, row[name]))
                if not low <= value <= high:
                    raise SystemExit("{} line {}: {} = {} is outside {}-{}".format(
                        path, line, name, value, low, high))
                if name == "injury_count":
                    value = min(value, risk_data.INJURY_MAX)
                values.append(value)
            if row[LABEL] not in ("0", "1"):
                raise SystemExit("{} line {}: {} must be 0 or 1, got {!r}".format(
                    path, line, LABEL, row[LABEL]))
            X.append(values)
            y.append(int(row[LABEL]))
    if not X:
        raise SystemExit("{}: no rows".format(path))
    return np.array(X, dtype=float), np.array(y, dtype=int)


def _comparison(cv: dict) -> str:
    if "rulesRocAuc" not in cv:
        return "No rules scores were available to compare against."
    return (
        "On the same held-out simulated days the rules alone score ROC AUC "
        "{:.3f} against the model's {:.3f}, and the model raises the rules' "
        "level on {:.1%} of them. The model claims no more accuracy than the "
        "rules today; what it adds is past injuries and recent pain weighed as "
        "the cited literature weighs them, and a path to learn from real "
        "outcomes once they exist."
    ).format(cv["rulesRocAuc"]["mean"], cv["rocAuc"]["mean"],
             cv["shareRaisedByModel"]["mean"])


def build_report(cv: dict, simulated_rows: int, seed: int, real_rows: int) -> dict:
    import sklearn

    return {
        "modelVersion": risk_model.MODEL_VERSION,
        "statement": STATEMENT,
        "data": {
            "kind": "simulated+real" if real_rows else "simulated",
            "seed": seed,
            "simulatedRows": simulated_rows,
            "coverageRows": "about {:.0%} of the simulated rows; trained on, "
                            "not scored".format(risk_data.COVERAGE_SHARE),
            "realRows": real_rows,
        },
        "features": list(risk_data.FEATURES),
        "simulation": {
            "sources": [
                "Tsilimigkras et al. 2024: acute surges in training load are "
                "prominent predictors of injury.",
                "Xu et al. 2025: random forests; prior injury, training "
                "intensity and recovery time are the best predictors.",
            ],
            "label": "injured within the week, drawn with probability "
                     "clip((expected risk + noise) / 100, {}, {})".format(
                         risk_data.P_MIN, risk_data.P_MAX),
            "baseline": risk_data.BASELINE,
            "loadPerPct": risk_data.LOAD_PER_PCT,
            "injuryPer": risk_data.INJURY_PER,
            "painPoints": list(risk_data.PAIN_POINTS),
            "recoveryCoefOnSquaredMean": dict(risk_data.RECOVERY_COEF),
            "noiseSd": risk_data.NOISE_SD,
            "coverageShare": risk_data.COVERAGE_SHARE,
        },
        "model": {
            "type": "RandomForestClassifier",
            "params": dict(risk_model.FOREST_PARAMS),
            "monotonicConstraints": dict.fromkeys(risk_data.FEATURES, 1),
            "score": "100 x predicted probability; final = max(model, rules)",
        },
        "crossValidation": cv,
        "comparisonWithRules": _comparison(cv),
        "sklearnVersion": sklearn.__version__,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.train_risk",
        description="Train the injury-risk model on simulated data (and "
                    "optionally real rows) and write its cross-validation report.",
    )
    parser.add_argument("--model-dir", default=os.environ.get("FITSYNC_MODEL_DIR", "models"))
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--rows", type=int, default=risk_data.ROWS,
                        help="simulated rows (default %(default)s)")
    parser.add_argument("--seed", type=int, default=risk_data.SEED)
    parser.add_argument("--real", help="CSV of real labelled rows to mix in")
    args = parser.parse_args(argv)

    # Everything that can be refused is checked before anything is written.
    real_X, real_y = (load_real(args.real) if args.real
                      else (np.empty((0, len(risk_data.FEATURES))), np.empty(0, dtype=int)))

    data = risk_data.simulate(rows=args.rows, seed=args.seed)
    X = np.vstack([data.X, real_X])
    y = np.concatenate([data.y, real_y])
    rules = np.concatenate([risk_data.rules_scores(data), np.full(len(real_y), np.nan)])
    evaluate = np.concatenate([~data.coverage, np.ones(len(real_y), dtype=bool)])

    cv = risk_model.cross_validate(X, y, rules_scores=rules, evaluate=evaluate,
                                   seed=args.seed)
    classifier = risk_model.fit(X, y, args.seed)

    os.makedirs(args.model_dir, exist_ok=True)
    model_path = os.path.join(args.model_dir, risk_model.MODEL_FILENAME)
    risk_model.save(classifier, model_path, real_rows=len(real_y), seed=args.seed)

    report = build_report(cv, args.rows, args.seed, len(real_y))
    report_dir = os.path.dirname(args.report)
    if report_dir:
        os.makedirs(report_dir, exist_ok=True)
    with open(args.report, "w") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    print("wrote {} and {}".format(model_path, args.report))
    print("held-out ROC AUC {:.3f}, Brier {:.3f} ({} rows scored; simulated data)".format(
        cv["rocAuc"]["mean"], cv["brier"]["mean"], cv["evaluatedRows"]))
    print("restart the ML service to pick up the new model")
    return 0


if __name__ == "__main__":
    sys.exit(main())
