"""The plan ranker's scikit-learn model and the ordering rule it serves.

A RandomForestClassifier predicts the chance a trainee logs a candidate
exercise rather than skipping or swapping it, from app/ranker_features.py's
inputs. It is trained on SIMULATED trainees (app/ranker_data.py) because
FitSync has almost no real record yet, and retrained on real rows as they
accumulate (app/train_ranker.py --real).

The forest is monotonic in the features with a stated direction
(ranker_features.MONOTONIC): a skip or a swap can never raise a score.

reorder() is the rule the service applies to the scores (app/ranker.py): it
moves an exercise only within a run of consecutive candidates sharing the
team's curated mark and the picked-equipment tier. Scores are grouped into
fixed bands RANK_MARGIN wide (0.50-0.55, 0.55-0.60, ...): an exercise moves up
only when its band is higher, and exercises in the same band keep the team's
order. This is not a minimum gap: 0.549 and 0.551 sit in different bands, so
noise from an input with no simulated effect can still reorder near-equal
choices whenever they straddle a band edge. Within one request the only such
input that differs between candidates of a run is beginner-friendly (for an
intermediate trainee; a beginner is offered only beginner-friendly ones):
goal, level, session length and split are the same for every candidate, and
the curated mark is equal within a run by construction.
"""
import math
from functools import lru_cache
from typing import Any, Dict, Hashable, List, Optional, Sequence

import numpy as np

from app import ranker_data, ranker_features

MODEL_FILENAME = "plan_ranker.joblib"
MODEL_VERSION = "ranker-rf-sim-1"

FOREST_PARAMS = {
    "n_estimators": 60,
    "max_depth": 12,
    "min_samples_leaf": 40,
    "max_features": None,
    "n_jobs": 1,
}
CV_FOLDS = 5
RANK_MARGIN = 0.05


def version_for(real_rows: int) -> str:
    return MODEL_VERSION.replace("-sim-", "-sim+real-") if real_rows else MODEL_VERSION


def build_classifier(seed: int = ranker_data.SEED):
    from sklearn.ensemble import RandomForestClassifier

    return RandomForestClassifier(
        random_state=seed,
        monotonic_cst=ranker_features.monotonic_cst(),
        **FOREST_PARAMS,
    )


def fit(X: np.ndarray, y: np.ndarray, seed: int = ranker_data.SEED):
    return build_classifier(seed).fit(X, y)


@lru_cache(maxsize=1)
def default_classifier():
    """The forest on the default seeded simulation, trained once per process."""
    data = ranker_data.simulate()
    return fit(data.X, data.y)


def bundle(classifier, real_rows: int = 0, seed: int = ranker_data.SEED) -> Dict[str, Any]:
    import sklearn

    return {
        "model": classifier,
        "version": version_for(real_rows),
        "features": list(ranker_features.FEATURES),
        "sklearnVersion": sklearn.__version__,
        "simulationSeed": seed,
        "realRows": real_rows,
    }


def save(classifier, path: str, real_rows: int = 0, seed: int = ranker_data.SEED) -> None:
    import joblib

    joblib.dump(bundle(classifier, real_rows, seed), path, compress=3)


def _summary(values: Sequence[float]) -> Dict[str, Any]:
    values = [float(v) for v in values]
    return {"mean": round(float(np.mean(values)), 4),
            "std": round(float(np.std(values)), 4),
            "folds": [round(v, 4) for v in values]}


def rules_tier_score(X: np.ndarray) -> np.ndarray:
    """What today's rules order by, as a score: picked equipment, then fit."""
    col = {name: i for i, name in enumerate(ranker_features.FEATURES)}
    return 2.0 * X[:, col["picked_equipment"]] + X[:, col["location_fit"]]


def cross_validate(X: np.ndarray, y: np.ndarray, groups: np.ndarray,
                   evaluate: Optional[np.ndarray] = None,
                   k: int = CV_FOLDS, seed: int = ranker_data.SEED) -> Dict[str, Any]:
    """Grouped stratified k-fold: one trainee's rows never sit on both sides.

    Each fold trains on every training row (coverage rows included) and is
    scored on the held-out rows `evaluate` marks. Reports the model's ROC AUC,
    log loss and accuracy, and the ROC AUC of today's rules tiers alone on the
    same rows -- what history and the rest add over the order the rules
    already give.
    """
    from sklearn.metrics import accuracy_score, log_loss, roc_auc_score
    from sklearn.model_selection import StratifiedGroupKFold

    if evaluate is None:
        evaluate = np.ones(len(y), dtype=bool)
    auc, loss, acc, rules_auc = [], [], [], []
    splitter = StratifiedGroupKFold(n_splits=k, shuffle=True, random_state=seed)
    for train, test in splitter.split(np.zeros((len(y), 1)), y, groups):
        test = test[evaluate[test]]
        probability = fit(X[train], y[train], seed).predict_proba(X[test])[:, 1]
        auc.append(roc_auc_score(y[test], probability))
        loss.append(log_loss(y[test], probability, labels=[0, 1]))
        acc.append(accuracy_score(y[test], probability >= 0.5))
        rules_auc.append(roc_auc_score(y[test], rules_tier_score(X[test])))
    return {
        "method": "StratifiedGroupKFold",
        "k": k,
        "shuffleSeed": seed,
        "rows": int(len(y)),
        "evaluatedRows": int(evaluate.sum()),
        "positiveRate": round(float(np.mean(y[evaluate])), 4),
        "rocAuc": _summary(auc),
        "logLoss": _summary(loss),
        "accuracy": _summary(acc),
        "rulesTierRocAuc": _summary(rules_auc),
    }


def reorder(run_keys: Sequence[Hashable], scores: Sequence[float]) -> List[int]:
    """Input indices in their new order.

    A run is a maximal stretch of consecutive items with an equal key. Runs
    keep their places; inside a run, items sort by floor(score / RANK_MARGIN)
    descending, and ties keep their input order (Python's sort is stable).
    """
    runs, run = [], -1
    for i, key in enumerate(run_keys):
        if i == 0 or key != run_keys[i - 1]:
            run += 1
        runs.append(run)

    def step(score: float) -> int:
        return math.floor(score / RANK_MARGIN + 1e-9)

    return sorted(range(len(run_keys)), key=lambda i: (runs[i], -step(scores[i])))
