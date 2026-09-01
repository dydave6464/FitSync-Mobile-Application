"""The model slot.

The rules engine is the baseline, permanently. A model is a re-ranker over
candidates the rules already produced -- never a replacement, and never a source
of new ones. See the design, section 8.

The invariant below is enforced here rather than trusted to training: `rank`
intersects whatever the model returns with what it was given. A model regression
can therefore make a plan duller; it can never make one unsafe.
"""
import logging
import os
from typing import Any, List, Optional, Sequence

from app.catalogue import Candidate
from app.config import Settings

MODEL_FILENAME = "plan_ranker.joblib"

logger = logging.getLogger(__name__)


class Ranker:
    def __init__(self, status: str, model: Optional[Any] = None):
        self.status = status
        self._model = model

    @property
    def mode(self) -> str:
        return "model" if self.status == "loaded" else "rules"

    @classmethod
    def load(cls, settings: Settings) -> "Ranker":
        path = os.path.join(settings.model_dir, MODEL_FILENAME)
        if not os.path.isfile(path):
            return cls(status="absent")
        try:
            import joblib

            return cls(status="loaded", model=joblib.load(path))
        except Exception as err:
            # Corrupt, truncated, version-mismatched, or unpicklable without a
            # library we do not have. None of those may fail a user's request.
            logger.error("model at %s is unusable, serving rules: %s", path, err)
            return cls(status="unusable")

    def rank(self, candidates: Sequence[Candidate]) -> List[Candidate]:
        original = list(candidates)
        if self.status != "loaded" or self._model is None:
            return original
        try:
            proposed = self._model.rank(original)
        except Exception as err:
            logger.error("model raised while ranking, serving rules: %s", err)
            return original

        # Subset or permutation only. Anything the model invented is dropped,
        # and order follows the model's preference among what survives.
        allowed = {c.exercise_id for c in original}
        seen = set()
        result = []
        for candidate in proposed:
            key = getattr(candidate, "exercise_id", None)
            if key in allowed and key not in seen:
                seen.add(key)
                result.append(candidate)
        return result or original
