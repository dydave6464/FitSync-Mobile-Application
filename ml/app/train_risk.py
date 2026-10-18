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
    user_id                          optional; who the row belongs to

Real rows are always scored in cross-validation, and they are kept apart from
the simulation in the report's row counts. Give user_id whenever it is known:
one user's rows are overlapping 3-day windows of the same weeks, and with it
cross-validation keeps each user's rows in one fold (StratifiedGroupKFold)
instead of letting the same week sit on both sides of a split. A model trained
with real rows is versioned "risk-rf-sim+real-N", so stored estimates say so.
Commit a report with real rows only on purpose: the test that checks the
committed report against the defaults skips it, so nothing then checks it.
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
USER = "user_id"

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


def load_real(path: str) -> Tuple[np.ndarray, np.ndarray, Optional[np.ndarray]]:
    """Real labelled rows from a CSV, validated, in FEATURES order.

    Returns X, y and each row's user_id, or None when the CSV has no user_id
    column.
    """
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in list(risk_data.FEATURES) + [LABEL]
                   if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit("{}: missing column(s): {}".format(path, ", ".join(missing)))
        has_user = USER in (reader.fieldnames or [])
        X: List[List[float]] = []
        y: List[int] = []
        users: List[str] = []
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
            if has_user:
                user = (row[USER] or "").strip()
                if not user:
                    raise SystemExit("{} line {}: {} is empty".format(path, line, USER))
                users.append(user)
            X.append(values)
            y.append(int(row[LABEL]))
    if not X:
        raise SystemExit("{}: no rows".format(path))
    groups = np.array(users, dtype=str) if has_user else None
    return np.array(X, dtype=float), np.array(y, dtype=int), groups


# Every comparison ends on what the model does and does not add, worded to
# claim no more than the probes below show.
_COMPARISON_TAIL = (
    "The model claims no more accuracy than the rules today. Its simulation's "
    "coefficients are judgement calls informed by the cited studies, not sizes "
    "measured in them, and the monotonic forest learns that simulation only "
    "coarsely: it barely separates moderate from severe recent pain or two from "
    "three past injuries, and it underestimates rare combinations, which the "
    "rules floor covers. What it adds today is a trained, retrainable path for "
    "when real outcomes exist."
)


def _comparison(cv: dict) -> str:
    if "rulesRocAuc" not in cv:
        return "No rules scores were available to compare against. " + _COMPARISON_TAIL
    if "rocAucWhereRulesKnown" in cv:
        # Real rows keep no raw answers, so the rules cannot be scored on them:
        # compare on the simulated rows both were scored on, and give the
        # model's figure over every row separately.
        head = (
            "On the held-out simulated days, the only rows the rules can be "
            "scored on (real rows keep no raw answers), the rules alone score "
            "ROC AUC {:.3f} against the model's {:.3f}; over every held-out row, "
            "real ones included, the model scores {:.3f}. The model raises the "
            "rules' level on {:.1%} of the simulated days. "
        ).format(cv["rulesRocAuc"]["mean"], cv["rocAucWhereRulesKnown"]["mean"],
                 cv["rocAuc"]["mean"], cv["shareRaisedByModel"]["mean"])
    else:
        head = (
            "On the same held-out simulated days the rules alone score ROC AUC "
            "{:.3f} against the model's {:.3f}, and the model raises the rules' "
            "level on {:.1%} of them. "
        ).format(cv["rulesRocAuc"]["mean"], cv["rocAuc"]["mean"],
                 cv["shareRaisedByModel"]["mean"])
    return head + _COMPARISON_TAIL


LIMITATIONS = [
    "The simulation's coefficients are judgement calls informed by the cited "
    "studies, not sizes measured in them: they encode each factor's direction "
    "and rough order, nothing more.",
    "The monotonic forest learns that simulation only coarsely. It barely "
    "separates moderate from severe recent pain or two from three past "
    "injuries, where the simulation adds 10 and 6 points (see probes).",
    "On days with a single risk factor, such as one past injury or moderate "
    "pain alone, it scores well above the simulation's own expected risk (see "
    "probes). So most of the days where the model beats the rules are "
    "overshoots of its own simulation, not risk the simulation supports.",
    "It underestimates rare combinations of risk factors by a wide margin, "
    "because few training days reach them. The rules floor covers those days: "
    "the final score is never below the rules' score.",
    "A calm day (every answer at its best, no extra load, no injuries, no "
    "pain) scores a little above 0, not 0 (see probes), because the "
    "simulation keeps every day's chance of injury at least 1% and so lifts "
    "the low end. Readiness on such a day reads a little under 100, and the "
    "deciding side can switch between model and rules on near-identical calm "
    "days.",
]

_BEST = {"sleepQuality": "excellent", "muscleSoreness": "none",
         "energy": "high", "stress": "very_low"}
_EVERYDAY = {"sleepQuality": "good", "muscleSoreness": "mild",
             "energy": "moderate", "stress": "low"}
_WORST = {"sleepQuality": "poor", "muscleSoreness": "severe",
          "energy": "very_low", "stress": "high"}


def _probe(checkin: dict, load: float = 0.0, injuries: int = 0,
           pain: str = "none") -> dict:
    return {"checkins": [dict(checkin)] * risk_data.WINDOW_DAYS, "load": load,
            "injuryHistory": [{"injuryId": i + 1} for i in range(injuries)],
            "recentPain": pain}


# Named days the report scores three ways -- model, simulation, rules -- so
# the limitations above can be checked against numbers, not taken on trust.
PROBES = [
    ("a calm day", _probe(_BEST)),
    ("one past injury alone", _probe(_BEST, injuries=1)),
    ("two past injuries alone", _probe(_BEST, injuries=2)),
    ("three past injuries alone", _probe(_BEST, injuries=3)),
    ("mild recent pain alone", _probe(_BEST, pain="mild")),
    ("moderate recent pain alone", _probe(_BEST, pain="moderate")),
    ("severe recent pain alone", _probe(_BEST, pain="severe")),
    ("everyday answers and moderate pain", _probe(_EVERYDAY, pain="moderate")),
    ("everyday answers and severe pain", _probe(_EVERYDAY, pain="severe")),
    ("the biggest week alone", _probe(_BEST, load=risk_data.LOAD_MAX)),
    ("the worst answers, three injuries and severe pain",
     _probe(_WORST, injuries=3, pain="severe")),
]


def probes(classifier) -> List[dict]:
    """PROBES scored by `classifier` through the service's own path."""
    from app import risk
    from app.schemas import InjuryRiskRequest

    model = risk_model.RiskModel(status="trained", classifier=classifier)
    scored = []
    for day, body in PROBES:
        payload = InjuryRiskRequest.model_validate(body)
        model_score = model.score(payload)
        rules = risk.rules_score(payload)
        simulation = float(risk_data.expected_risk(risk_model.features_for(payload))[0])
        scored.append({"day": day, "model": model_score,
                       "simulation": round(simulation, 2), "rules": rules,
                       "final": max(model_score, rules)})
    return scored


def build_report(cv: dict, simulated_rows: int, seed: int, real_rows: int,
                 probed: Optional[List[dict]] = None,
                 real_users: Optional[int] = None) -> dict:
    import sklearn

    return {
        "modelVersion": risk_model.version_for(real_rows),
        "statement": STATEMENT,
        "limitations": list(LIMITATIONS),
        "data": {
            "kind": "simulated+real" if real_rows else "simulated",
            "seed": seed,
            "simulatedRows": simulated_rows,
            "coverageRows": "about {:.0%} of the simulated rows; trained on, "
                            "not scored".format(risk_data.COVERAGE_SHARE),
            "realRows": real_rows,
            "realUsers": real_users,
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
        "probes": probed or [],
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
    real_X, real_y, real_users = (
        load_real(args.real) if args.real
        else (np.empty((0, len(risk_data.FEATURES))), np.empty(0, dtype=int), None))

    data = risk_data.simulate(rows=args.rows, seed=args.seed)
    X = np.vstack([data.X, real_X])
    y = np.concatenate([data.y, real_y])
    rules = np.concatenate([risk_data.rules_scores(data), np.full(len(real_y), np.nan)])
    evaluate = np.concatenate([~data.coverage, np.ones(len(real_y), dtype=bool)])

    # Grouped only when real rows say whose they are; each simulated row is a
    # group of its own, since simulated days are drawn independently.
    groups = None
    if real_users is not None:
        groups = np.concatenate([
            np.array(["sim-{}".format(i) for i in range(len(data.y))]),
            np.char.add("real-", real_users),
        ])
    cv = risk_model.cross_validate(X, y, rules_scores=rules, evaluate=evaluate,
                                   seed=args.seed, groups=groups)
    classifier = risk_model.fit(X, y, args.seed)

    os.makedirs(args.model_dir, exist_ok=True)
    model_path = os.path.join(args.model_dir, risk_model.MODEL_FILENAME)
    risk_model.save(classifier, model_path, real_rows=len(real_y), seed=args.seed)

    report = build_report(
        cv, args.rows, args.seed, len(real_y), probed=probes(classifier),
        real_users=None if real_users is None else len(set(real_users.tolist())))
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
