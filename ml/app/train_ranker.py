"""Train the plan ranker and write its cross-validation report.

    cd ml
    .venv/bin/python -m app.train_ranker                   # simulated only
    .venv/bin/python -m app.train_ranker --real real.csv   # mix in real rows

Writes models/plan_ranker.joblib (git-ignored; FITSYNC_MODEL_DIR or
--model-dir moves it) and reports/plan_ranker_cv.json (committed). The
running service has no auto-reload: restart it to pick up a new model file.

--real takes the CSV `npm run export:ranker` writes in server/ (columns:
CSV_COLUMNS below). Real rows are always scored in cross-validation, grouped
by user_id so one person's rows never sit on both sides of a fold. A model
trained with real rows is versioned "ranker-rf-sim+real-1". Commit a report
with real rows only on purpose: the test that checks the committed report
against the defaults skips it.
"""
import argparse
import csv
import json
import os
import sys
from typing import List, Optional, Tuple

import numpy as np

from app import ranker_data, ranker_features, ranker_model

DEFAULT_REPORT = os.path.join("reports", "plan_ranker_cv.json")

CSV_COLUMNS = (
    "user_id", "event_date", "kind", "main_goal", "fitness_level",
    "training_location", "session_length_min", "split_style",
    "health_caution", "exercise_id", "mark", "beginner_friendly",
    "equipment_name", "picked_equipment", "muscle_group",
    "days_since_trained", "times_done", "times_skipped", "times_swapped",
    "done",
)
KINDS = ("prescribed", "swap")

STATEMENT = (
    "This model is trained on simulated trainees built from published "
    "findings on exercise adherence and muscle soreness, not on real users, "
    "and it is retrained on real workout logs and swaps as they accumulate. "
    "The cross-validation metrics measure how well it learned that "
    "simulation; they say nothing about how real people choose exercises. "
    "The rules still decide which exercises are safe; the model only orders "
    "exercises within the team's curated choices."
)

LIMITATIONS = [
    "The cited studies measure whether people keep exercising, not which "
    "exercise they choose; applying them to single exercises is FitSync's "
    "assumption.",
    "The simulation's weights encode direction and rough ordering only, not "
    "measured effect sizes.",
    "Goal, fitness level, session length, split and curated mark have no "
    "simulated effect; only real rows can teach them.",
    "A beginner or cautioned trainee is never offered a non-beginner-friendly "
    "exercise, so that combination is not simulated.",
    "The model orders only within runs of equal curated mark and "
    "picked-equipment tier, comparing scores in fixed {:.0f}-point bands "
    "(0.50-0.55, 0.55-0.60, ...): a candidate moves up only when its band is "
    "higher. This is not a minimum gap: two candidates less than {:.0f} "
    "points apart reorder when they fall on either side of a band edge, and "
    "keep the team's order when they share a band. It never adds, removes or "
    "reclassifies an exercise.".format(
        ranker_model.RANK_MARGIN * 100, ranker_model.RANK_MARGIN * 100),
]

SOURCES = [
    "Rodrigues et al. 2020, 2022; Cid et al. 2025; Conti et al. 2026: past "
    "exercise behaviour is the strongest predictor of future adherence.",
    "Hotfiel et al. 2018; Fu et al. 2024; Kanda et al. 2013: delayed-onset "
    "muscle soreness peaks 24-72 h after training.",
    "Jakicic et al. 1997; Morgan et al. 2016: owned equipment goes with more "
    "activity; unfamiliar gym equipment is a common barrier.",
    "Collado-Mateo et al. 2021; Tross 2024: programmes fitted to the person's "
    "setting support adherence.",
]


def _situation(row: dict, path: str, line: int) -> dict:
    def number(name, low, high):
        raw = row.get(name)
        try:
            value = float(raw)
        except (TypeError, ValueError):
            raise SystemExit("{} line {}: {} is not a number: {!r}".format(path, line, name, raw))
        if not low <= value <= high:
            raise SystemExit("{} line {}: {} = {} is outside {}-{}".format(
                path, line, name, value, low, high))
        return value

    def flag(name):
        if row.get(name) not in ("0", "1"):
            raise SystemExit("{} line {}: {} must be 0 or 1, got {!r}".format(
                path, line, name, row.get(name)))
        return row[name] == "1"

    days_raw = (row.get("days_since_trained") or "").strip()
    return {
        "mainGoal": row.get("main_goal") or None,
        "fitnessLevel": row.get("fitness_level") or None,
        "trainingLocation": row.get("training_location") or None,
        "sessionLengthMin": number("session_length_min", 0, 240),
        "splitStyle": row.get("split_style") or None,
        "healthCaution": flag("health_caution"),
        "mark": row.get("mark") or None,
        "beginnerFriendly": flag("beginner_friendly"),
        "pickedEquipment": flag("picked_equipment"),
        "equipmentName": row.get("equipment_name") or None,
        "daysSinceTrained": None if not days_raw else number("days_since_trained", 0, 10000),
        "timesDone": number("times_done", 0, 10000),
        "timesSkipped": number("times_skipped", 0, 10000),
        "timesSwapped": number("times_swapped", 0, 10000),
    }


def load_real(path: str) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Real labelled rows from the export CSV: X in FEATURES order, y, user ids."""
    with open(path, newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in CSV_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            raise SystemExit("{}: missing column(s): {}".format(path, ", ".join(missing)))
        X: List[List[float]] = []
        y: List[int] = []
        users: List[str] = []
        for line, row in enumerate(reader, start=2):
            if row["kind"] not in KINDS:
                raise SystemExit("{} line {}: kind must be one of {}, got {!r}".format(
                    path, line, "/".join(KINDS), row["kind"]))
            if row["done"] not in ("0", "1"):
                raise SystemExit("{} line {}: done must be 0 or 1, got {!r}".format(
                    path, line, row["done"]))
            user = (row["user_id"] or "").strip()
            if not user:
                raise SystemExit("{} line {}: user_id is empty".format(path, line))
            X.append(ranker_features.encode(_situation(row, path, line)))
            y.append(int(row["done"]))
            users.append(user)
    if not X:
        raise SystemExit("{}: no rows".format(path))
    return np.array(X, dtype=float), np.array(y, dtype=int), np.array(users, dtype=str)


def _probe_situation(**changes) -> dict:
    base = {"mainGoal": "general_fitness", "fitnessLevel": "beginner",
            "trainingLocation": "home_gym", "sessionLengthMin": 45,
            "splitStyle": "full_body", "healthCaution": False, "mark": "first",
            "beginnerFriendly": True, "pickedEquipment": True,
            "equipmentName": "dumbbell", "daysSinceTrained": 7, "timesDone": 1,
            "timesSkipped": 0, "timesSwapped": 0}
    return dict(base, **changes)


# Each probe: a trainee, three candidates in one run (same mark, same
# picked tier) in the team's order, and what the model does with them.
PROBES = [
    ("home beginner; the first candidate's muscle was trained yesterday", [
        ("trained yesterday", _probe_situation(daysSinceTrained=1, timesDone=2)),
        ("rested a week", _probe_situation()),
        ("rested, done twice", _probe_situation(timesDone=2)),
    ]),
    ("gym intermediate who swapped the first candidate out twice", [
        ("swapped out twice", _probe_situation(fitnessLevel="intermediate",
                                               trainingLocation="commercial_gym",
                                               equipmentName="barbell",
                                               timesDone=0, timesSwapped=2)),
        ("never tried", _probe_situation(fitnessLevel="intermediate",
                                         trainingLocation="commercial_gym",
                                         equipmentName="barbell", timesDone=0)),
        ("done three times", _probe_situation(fitnessLevel="intermediate",
                                              trainingLocation="commercial_gym",
                                              equipmentName="barbell", timesDone=3)),
    ]),
    ("new user, no history, three equal candidates", [
        ("candidate A", _probe_situation(fitnessLevel="new", timesDone=0, daysSinceTrained=None)),
        ("candidate B", _probe_situation(fitnessLevel="new", timesDone=0, daysSinceTrained=None)),
        ("candidate C", _probe_situation(fitnessLevel="new", timesDone=0, daysSinceTrained=None)),
    ]),
]


def probes(classifier) -> List[dict]:
    out = []
    for name, candidates in PROBES:
        X = np.array([ranker_features.encode(s) for _, s in candidates])
        scores = classifier.predict_proba(X)[:, 1]
        order = ranker_model.reorder([("first", True)] * len(candidates), scores.tolist())
        out.append({
            "trainee": name,
            "teamOrder": [label for label, _ in candidates],
            "scores": {label: round(float(s), 4) for (label, _), s in zip(candidates, scores)},
            "order": [candidates[i][0] for i in order],
        })
    return out


def top_pick_changed_share(classifier, data) -> float:
    """Share of simulated trainees whose first pick the model changes.

    Each trainee's candidates are put in the rules' order (curated mark, then
    picked equipment, then location fit) and reordered as the service would.
    """
    col = {name: i for i, name in enumerate(ranker_features.FEATURES)}
    scores = classifier.predict_proba(data.X)[:, 1]
    changed = trainees = 0
    for t in np.unique(data.trainee[~data.coverage]):
        rows = np.flatnonzero(data.trainee == t)
        rules = sorted(rows, key=lambda r: (data.X[r, col["mark"]],
                                            -data.X[r, col["picked_equipment"]],
                                            -data.X[r, col["location_fit"]], r))
        keys = [(data.X[r, col["mark"]], data.X[r, col["picked_equipment"]]) for r in rules]
        order = ranker_model.reorder(keys, [scores[r] for r in rules])
        trainees += 1
        changed += int(order[0] != 0)
    return round(changed / trainees, 4) if trainees else 0.0


def build_report(cv: dict, simulated_rows: int, seed: int, real_rows: int,
                 probed: List[dict], changed_share: float,
                 real_users: Optional[int] = None) -> dict:
    import sklearn

    return {
        "modelVersion": ranker_model.version_for(real_rows),
        "statement": STATEMENT,
        "limitations": list(LIMITATIONS),
        "data": {
            "kind": "simulated+real" if real_rows else "simulated",
            "seed": seed,
            "simulatedRows": simulated_rows,
            "candidatesPerTrainee": ranker_data.CANDIDATES_PER_TRAINEE,
            "coverageRows": "about {:.0%} of the simulated trainees; trained on, "
                            "not scored".format(ranker_data.COVERAGE_SHARE),
            "realRows": real_rows,
            "realUsers": real_users,
        },
        "features": list(ranker_features.FEATURES),
        "simulation": {
            "sources": list(SOURCES),
            "label": "did it (logged a completed set), drawn with probability "
                     "sigmoid(log-odds + noise), clipped to [{}, {}]".format(
                         ranker_data.P_MIN, ranker_data.P_MAX),
            "baseLogit": ranker_data.BASE_LOGIT,
            "donePer": ranker_data.DONE_PER,
            "skippedPer": ranker_data.SKIPPED_PER,
            "swappedPer": ranker_data.SWAPPED_PER,
            "restPenaltyByDays": list(ranker_data.REST_PENALTY),
            "pickedBonus": ranker_data.PICKED_BONUS,
            "locationBonus": ranker_data.LOCATION_BONUS,
            "noiseSd": ranker_data.NOISE_SD,
        },
        "model": {
            "type": "RandomForestClassifier",
            "params": dict(ranker_model.FOREST_PARAMS),
            "monotonicConstraints": dict(ranker_features.MONOTONIC),
            "ordering": "within runs of equal (curated mark, picked equipment), "
                        "by score band floor(score / {}) descending; equal bands "
                        "keep the team's order".format(ranker_model.RANK_MARGIN),
        },
        "crossValidation": cv,
        "topPickChangedShare": changed_share,
        "probes": probed,
        "sklearnVersion": sklearn.__version__,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.train_ranker",
        description="Train the plan ranker on simulated data (and optionally "
                    "real rows) and write its cross-validation report.",
    )
    parser.add_argument("--model-dir", default=os.environ.get("FITSYNC_MODEL_DIR", "models"))
    parser.add_argument("--report", default=DEFAULT_REPORT)
    parser.add_argument("--rows", type=int, default=ranker_data.ROWS)
    parser.add_argument("--seed", type=int, default=ranker_data.SEED)
    parser.add_argument("--real", help="CSV from `npm run export:ranker`")
    args = parser.parse_args(argv)

    real_X, real_y, real_users = (
        load_real(args.real) if args.real
        else (np.empty((0, len(ranker_features.FEATURES))), np.empty(0, dtype=int),
              np.empty(0, dtype=str)))

    data = ranker_data.simulate(rows=args.rows, seed=args.seed)
    X = np.vstack([data.X, real_X])
    y = np.concatenate([data.y, real_y])
    groups = np.concatenate([
        np.char.add("sim-", data.trainee.astype(str)),
        np.char.add("real-", real_users.astype(str)),
    ])
    evaluate = np.concatenate([~data.coverage, np.ones(len(real_y), dtype=bool)])
    cv = ranker_model.cross_validate(X, y, groups=groups, evaluate=evaluate, seed=args.seed)
    classifier = ranker_model.fit(X, y, args.seed)

    os.makedirs(args.model_dir, exist_ok=True)
    model_path = os.path.join(args.model_dir, ranker_model.MODEL_FILENAME)
    ranker_model.save(classifier, model_path, real_rows=len(real_y), seed=args.seed)

    report = build_report(
        cv, args.rows, args.seed, len(real_y), probes(classifier),
        top_pick_changed_share(classifier, data),
        real_users=len(set(real_users.tolist())) if len(real_y) else None)
    report_dir = os.path.dirname(args.report)
    if report_dir:
        os.makedirs(report_dir, exist_ok=True)
    with open(args.report, "w") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    print("wrote {} and {}".format(model_path, args.report))
    print("held-out ROC AUC {:.3f} (rules tiers alone {:.3f}); top pick changed for "
          "{:.0%} of simulated trainees".format(
              cv["rocAuc"]["mean"], cv["rulesTierRocAuc"]["mean"],
              report["topPickChangedShare"]))
    print("restart the ML service to pick up the new model")
    return 0


if __name__ == "__main__":
    sys.exit(main())
