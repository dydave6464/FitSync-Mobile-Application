"""The scikit-learn injury-risk model, with the rules as its safety floor.

A RandomForestClassifier predicts the chance of an injury within the week from
the 3-day check-ins, the training-load index, past injuries and recent pain.
It is trained on SIMULATED user-days built from published injury risk factors
(app/risk_data.py), because FitSync has no real injury outcomes yet, and it is
retrained on real check-in outcomes as they accumulate (app/train_risk.py,
--real). It is not validated against real injuries and claims no more
accuracy than the rules today.

How its score is used:

- model score = 100 x the predicted probability. The simulation sets the
  probability on the rules' 0-100 scale, so the two are comparable.
- final score = max(model score, rules score). The model can raise an estimate,
  never lower it below the rules (app/risk.py), so a model regression can make
  the estimate more cautious but never less.
- The forest is constrained to be monotonic in every input (each is coded so
  that higher is riskier), so a worse answer can never lower the model's
  score, and the max of two monotonic scores is monotonic too.
- Any failure -- no model, a corrupt file, an error or a nonsense value at
  request time -- serves the rules alone. It must never fail the endpoint.
"""
import logging
import math
import os
from functools import lru_cache
from typing import Any, Dict, Optional, Sequence

import numpy as np

from app import risk, risk_data
from app.schemas import InjuryRiskRequest, InjuryRiskResponse

MODEL_FILENAME = "injury_risk.joblib"
# Bumped whenever the simulation, the features or the forest change, so a
# stored estimate can be traced to what produced it. "sim" says what it was
# trained on.
MODEL_VERSION = "risk-rf-sim-1"


def version_for(real_rows: int) -> str:
    """MODEL_VERSION, marked "sim+real" when real rows were mixed in.

    So a stored estimate says whether real outcomes shaped the model that made
    it. Fits the server's model_version VARCHAR(40).
    """
    return MODEL_VERSION.replace("-sim-", "-sim+real-") if real_rows else MODEL_VERSION

# Small on purpose: trains in a few seconds at startup and saves well under
# 2 MB. min_samples_leaf keeps each leaf's probability an average over enough
# days to be stable rather than a memorised handful.
FOREST_PARAMS = {
    "n_estimators": 60,
    "max_depth": 12,
    "min_samples_leaf": 20,
    "max_features": None,
    "n_jobs": 1,
}

CV_FOLDS = 5

logger = logging.getLogger(__name__)

_ORDINALS = tuple(
    {answer: index for index, answer in enumerate(order)}
    for _, order in risk_data.CHECKIN_ORDERS
)
_PAIN_ORDINAL = {answer: index for index, answer in enumerate(risk_data.PAIN_ORDER)}


def features_for(payload: InjuryRiskRequest) -> np.ndarray:
    """One request as a (1, len(FEATURES)) row, in risk_data.FEATURES order.

    Read the way the rules read it: each check-in answer averaged over every
    check-in in the window, an unrecognised answer or entry counting as the
    best (it adds nothing to the rules either), and no check-ins at all as
    nothing reported. Values are clipped to the ranges the model was trained
    on, so an out-of-range load reads as the largest surge it knows.
    """
    checkins = payload.checkins
    recovery = []
    for (field, _), ordinal in zip(risk_data.CHECKIN_ORDERS, _ORDINALS):
        if checkins:
            recovery.append(sum(
                ordinal.get(risk.answer_in(ordinal, c, field), 0) for c in checkins
            ) / len(checkins))
        else:
            recovery.append(0.0)
    load = min(max(payload.load, 0.0), risk_data.LOAD_MAX)
    injuries = min(len(payload.injuryHistory), risk_data.INJURY_MAX)
    pain = _PAIN_ORDINAL.get(payload.recentPain, 0)
    return np.array([recovery + [load, injuries, pain]], dtype=float)


def build_classifier(seed: int = risk_data.SEED):
    from sklearn.ensemble import RandomForestClassifier

    return RandomForestClassifier(
        random_state=seed,
        # +1 for every feature: higher is riskier for all of them.
        monotonic_cst=[1] * len(risk_data.FEATURES),
        **FOREST_PARAMS,
    )


def fit(X: np.ndarray, y: np.ndarray, seed: int = risk_data.SEED):
    return build_classifier(seed).fit(X, y)


@lru_cache(maxsize=1)
def default_classifier():
    """The forest trained on the default seeded simulation, once per process.

    What the service falls back to when no model file is on disk. Cached so
    that every app built in one process (the test suite builds dozens) shares
    one training run.
    """
    data = risk_data.simulate()
    return fit(data.X, data.y)


def bundle(classifier, real_rows: int = 0, seed: int = risk_data.SEED) -> Dict[str, Any]:
    import sklearn

    return {
        "model": classifier,
        "version": version_for(real_rows),
        "features": list(risk_data.FEATURES),
        "sklearnVersion": sklearn.__version__,
        "simulationSeed": seed,
        "realRows": real_rows,
    }


def save(classifier, path: str, real_rows: int = 0, seed: int = risk_data.SEED) -> None:
    import joblib

    joblib.dump(bundle(classifier, real_rows, seed), path, compress=3)


def _summary(values: Sequence[float]) -> Dict[str, Any]:
    values = [float(v) for v in values]
    return {
        "mean": round(float(np.mean(values)), 4),
        "std": round(float(np.std(values)), 4),
        "folds": [round(v, 4) for v in values],
    }


def folds(y: np.ndarray, groups: Optional[np.ndarray] = None,
          k: int = CV_FOLDS, seed: int = risk_data.SEED):
    """(train, test) index pairs: stratified, and grouped when groups are given.

    Real rows from one user are overlapping 3-day windows of the same weeks;
    split freely, the same week would sit on both sides of a fold and flatter
    the metrics. With groups (a user id per real row, a unique id per simulated
    row) StratifiedGroupKFold keeps each user's rows in one fold.
    """
    from sklearn.model_selection import StratifiedGroupKFold, StratifiedKFold

    placeholder = np.zeros((len(y), 1))
    if groups is None:
        return StratifiedKFold(n_splits=k, shuffle=True,
                               random_state=seed).split(placeholder, y)
    return StratifiedGroupKFold(n_splits=k, shuffle=True,
                                random_state=seed).split(placeholder, y, groups)


def cross_validate(X: np.ndarray, y: np.ndarray,
                   rules_scores: Optional[np.ndarray] = None,
                   evaluate: Optional[np.ndarray] = None,
                   k: int = CV_FOLDS, seed: int = risk_data.SEED,
                   groups: Optional[np.ndarray] = None) -> Dict[str, Any]:
    """Stratified k-fold cross-validation of the forest.

    Each fold trains on every training row, coverage rows included, but is
    scored only on the held-out rows `evaluate` marks (all of them when it is
    None). The trainer passes the everyday and real rows: the coverage rows
    are spread evenly and lean risky, and scoring them would flatter the AUC.

    Per held-out fold: ROC AUC and Brier score of the model's probability, and,
    where the rules' score is known for a row (every simulated row; not real
    CSV rows, whose raw answers are not kept), how often the model's own level
    matches the rules' level, how often the final max(model, rules) level is
    above the rules' level, and the rules' own ROC AUC on the same rows for
    comparison. When the rules' score is missing for some rows (real ones),
    the model's ROC AUC is also given on just the rows the rules were scored
    on, so the two are compared on the same days. On simulated data these say
    how well the model learned the simulation, not how it would do on real
    injuries.
    """
    from sklearn.metrics import brier_score_loss, roc_auc_score

    if evaluate is None:
        evaluate = np.ones(len(y), dtype=bool)
    auc, brier, agree, raised, rules_auc, model_auc_known = [], [], [], [], [], []
    for train, test in folds(y, groups, k, seed):
        test = test[evaluate[test]]
        probability = fit(X[train], y[train], seed).predict_proba(X[test])[:, 1]
        auc.append(roc_auc_score(y[test], probability))
        brier.append(brier_score_loss(y[test], probability))
        if rules_scores is None:
            continue
        known = ~np.isnan(rules_scores[test])
        if not known.any():
            continue
        rules = rules_scores[test][known]
        model = np.round(probability[known] * 100.0, 2)
        rules_levels = [risk.level_for(s) for s in rules]
        model_levels = [risk.level_for(s) for s in model]
        final_levels = [risk.level_for(s) for s in np.maximum(model, rules)]
        agree.append(np.mean([m == r for m, r in zip(model_levels, rules_levels)]))
        raised.append(np.mean([f != r for f, r in zip(final_levels, rules_levels)]))
        if len(set(y[test][known])) == 2:
            rules_auc.append(roc_auc_score(y[test][known], rules))
            if not known.all():
                model_auc_known.append(roc_auc_score(y[test][known], probability[known]))

    result = {
        "method": "StratifiedKFold" if groups is None else "StratifiedGroupKFold",
        "k": k,
        "shuffleSeed": seed,
        "rows": int(len(y)),
        "evaluatedRows": int(evaluate.sum()),
        "positiveRate": round(float(np.mean(y[evaluate])), 4),
        "rocAuc": _summary(auc),
        "brier": _summary(brier),
    }
    if agree:
        result["levelAgreementWithRules"] = _summary(agree)
        result["shareRaisedByModel"] = _summary(raised)
    if rules_auc:
        result["rulesRocAuc"] = _summary(rules_auc)
    if model_auc_known:
        result["rocAucWhereRulesKnown"] = _summary(model_auc_known)
    return result


class RiskModel:
    """The loaded (or in-process trained) forest, or its absence.

    status is what /health reports: "loaded" from a file, "trained" in this
    process because no file was there, "absent" when there is no usable model.
    """

    def __init__(self, status: str, classifier: Optional[Any] = None,
                 version: Optional[str] = None):
        self.status = status
        self._classifier = classifier
        self.version = version if classifier is not None else None

    @classmethod
    def load(cls, settings) -> "RiskModel":
        """The model file if it is there and sound, else one trained in-process.

        A missing file is the normal state of a fresh checkout (models/*.joblib
        is git-ignored), so the service trains the default model from the
        seeded simulation -- about a second -- and keeps it in memory; it never
        writes into its model directory itself. A file that is there but
        unusable is a different story: someone put it there on purpose, so
        quietly replacing it with the default would hide the problem. It is
        logged and the rules serve alone.
        """
        path = os.path.join(settings.model_dir, MODEL_FILENAME)
        if not os.path.isfile(path):
            try:
                return cls(status="trained", classifier=default_classifier(),
                           version=MODEL_VERSION)
            except Exception as err:
                logger.error("could not train the injury-risk model in-process, "
                             "serving rules: %s", err)
                return cls(status="absent")
        try:
            import joblib

            stored = joblib.load(path)
            if not isinstance(stored, dict):
                raise ValueError("not a model bundle (expected a dict)")
            if list(stored.get("features") or []) != list(risk_data.FEATURES):
                raise ValueError("trained on features {!r}, expected {!r}".format(
                    stored.get("features"), list(risk_data.FEATURES)))
            classifier = stored.get("model")
            if not hasattr(classifier, "predict_proba"):
                raise ValueError("bundle holds no classifier")
            return cls(status="loaded", classifier=classifier,
                       version=str(stored.get("version") or "unknown"))
        except Exception as err:
            # Corrupt, truncated, version-mismatched, or trained on other
            # columns. None of those may fail a user's request.
            logger.error("injury-risk model at %s is unusable, serving rules: %s",
                         path, err)
            return cls(status="absent")

    @property
    def usable(self) -> bool:
        return self._classifier is not None and self.status in ("loaded", "trained")

    def score(self, payload: InjuryRiskRequest) -> float:
        """100 x the predicted probability, to two decimals. May raise."""
        probability = float(self._classifier.predict_proba(features_for(payload))[0, 1])
        if not math.isfinite(probability) or not 0.0 <= probability <= 1.0:
            raise ValueError("model returned probability {!r}".format(probability))
        return round(probability * 100.0, 2)


def estimate(payload: InjuryRiskRequest, model: Optional[RiskModel]) -> InjuryRiskResponse:
    """The final estimate: the rules, raised by the model when it scores higher."""
    # First, so a non-finite load is refused exactly as the rules refuse it.
    floor = risk.estimate(payload)
    if model is None or not model.usable:
        return floor

    try:
        model_score = model.score(payload)
    except Exception as err:
        logger.error("injury-risk model failed on a request, serving rules: %s", err)
        return floor

    if model_score > floor.trainingLoadScore:
        return floor.model_copy(update={
            "riskLevel": risk.level_for(model_score),
            "trainingLoadScore": model_score,
            "source": "model",
            "modelVersion": model.version,
        })
    return floor.model_copy(update={"modelVersion": model.version})
