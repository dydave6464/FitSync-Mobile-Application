"""The plan ranker: orders the candidates the rules already produced.

The rules engine is the baseline, permanently. The model is a re-ranker over
candidates the rules produced -- never a replacement, never a source of new
ones -- and these invariants live HERE, not in training:

- only the exact Candidate objects passed in leave rank(), each once;
- an exercise moves only within a run of consecutive candidates sharing the
  team's curated mark and the picked-equipment tier (ranker_model.reorder),
  so first choices stay ahead of alternatives and body-weight fill-ins never
  jump ahead of equipment the user picked;
- any failure -- no model, no context, a missing attribute, an exception, a
  score outside [0, 1] -- serves the rules' order.

A model regression can make a plan duller; it can never make one unsafe.
"""
import logging
import math
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Sequence

import numpy as np

from app import ranker_features, ranker_model
from app.catalogue import Candidate, CandidateAttributes
from app.config import Settings
from app.schemas import PlanHistory

MODEL_FILENAME = ranker_model.MODEL_FILENAME

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RankContext:
    main_goal: Optional[str]
    fitness_level: Optional[str]
    training_location: Optional[str]
    session_length_min: int
    split_style: str
    health_caution: bool
    attributes: Dict[int, CandidateAttributes]
    history: PlanHistory = field(default_factory=PlanHistory)


class Ranker:
    """status is what /health reports: "loaded" (a file), "trained" (in this
    process), "absent" (no model could be trained) or "unusable" (a file is
    there but cannot be used -- someone put it there on purpose, so it is not
    silently replaced)."""

    def __init__(self, status: str, classifier: Optional[Any] = None,
                 version: Optional[str] = None):
        self.status = status
        self._classifier = classifier
        self.version = version if classifier is not None else None

    @property
    def mode(self) -> str:
        return "model" if self.usable else "rules"

    @property
    def usable(self) -> bool:
        return self._classifier is not None and self.status in ("loaded", "trained")

    @classmethod
    def trained_in_process(cls) -> "Ranker":
        try:
            return cls(status="trained", classifier=ranker_model.default_classifier(),
                       version=ranker_model.MODEL_VERSION)
        except Exception as err:
            logger.error("could not train the plan ranker in-process, serving rules: %s", err)
            return cls(status="absent")

    @classmethod
    def load(cls, settings: Settings) -> "Ranker":
        path = os.path.join(settings.model_dir, MODEL_FILENAME)
        if not os.path.isfile(path):
            return cls.trained_in_process()
        try:
            import joblib
            import sklearn

            stored = joblib.load(path)
            if not isinstance(stored, dict):
                raise ValueError("not a model bundle (expected a dict)")
            if list(stored.get("features") or []) != list(ranker_features.FEATURES):
                raise ValueError("trained on features {!r}, expected {!r}".format(
                    stored.get("features"), list(ranker_features.FEATURES)))
            classifier = stored.get("model")
            if not hasattr(classifier, "predict_proba"):
                raise ValueError("bundle holds no classifier")
            if stored.get("sklearnVersion") != sklearn.__version__:
                logger.warning(
                    "plan ranker at %s was saved with scikit-learn %s but %s is "
                    "installed; training the default model in-process instead. "
                    "Re-run app.train_ranker to replace the file.",
                    path, stored.get("sklearnVersion") or "(not recorded)",
                    sklearn.__version__)
                return cls.trained_in_process()
            return cls(status="loaded", classifier=classifier,
                       version=str(stored.get("version") or "unknown"))
        except Exception as err:
            logger.error("plan ranker at %s is unusable, serving rules: %s", path, err)
            return cls(status="unusable")

    def rank(self, candidates: Sequence[Candidate],
             context: Optional[RankContext] = None) -> List[Candidate]:
        original = list(candidates)
        if not self.usable or context is None or len(original) < 2:
            return original
        try:
            order = self._order(original, context)
        except Exception as err:
            logger.error("plan ranker failed, serving rules: %s", err)
            return original
        return [original[i] for i in order]

    def _order(self, original: List[Candidate], context: RankContext) -> List[int]:
        rows, keys = [], []
        for c in original:
            attrs = context.attributes.get(c.exercise_id)
            if attrs is None:
                raise ValueError("no attributes for exercise {}".format(c.exercise_id))
            done = context.history.exercises.get(str(c.exercise_id))
            rows.append(ranker_features.encode({
                "mainGoal": context.main_goal,
                "fitnessLevel": context.fitness_level,
                "trainingLocation": context.training_location,
                "sessionLengthMin": context.session_length_min,
                "splitStyle": context.split_style,
                "healthCaution": context.health_caution,
                "mark": attrs.mark,
                "beginnerFriendly": attrs.beginner_friendly,
                "pickedEquipment": attrs.picked,
                "equipmentName": attrs.equipment_name,
                "daysSinceTrained": context.history.muscleDaysAgo.get(c.muscle_group),
                "timesDone": done.done if done else 0,
                "timesSkipped": done.skipped if done else 0,
                "timesSwapped": done.swapped if done else 0,
            }))
            keys.append((attrs.mark, attrs.picked))
        scores = self._classifier.predict_proba(np.array(rows, dtype=float))[:, 1]
        scores = [float(s) for s in scores]
        if len(scores) != len(original) or not all(
                math.isfinite(s) and 0.0 <= s <= 1.0 for s in scores):
            raise ValueError("model returned unusable scores")
        order = ranker_model.reorder(keys, scores)
        if sorted(order) != list(range(len(original))):
            raise ValueError("reorder lost or duplicated a candidate")
        return order
