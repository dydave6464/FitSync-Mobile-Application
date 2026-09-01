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

        # Only the trusted originals may leave this method. A model that returns
        # an object of its own -- even one spoofing a legitimate exercise_id --
        # must not get its `name` into the plan, because `name` is exactly what
        # savePlan resolves and what the user is told to do.
        by_id = {c.exercise_id: c for c in original}

        try:
            proposed = self._model.rank(original)
            seen = set()
            result = []
            for candidate in proposed:
                key = getattr(candidate, "exercise_id", None)
                if key in by_id and key not in seen:
                    seen.add(key)
                    result.append(by_id[key])
        except Exception as err:
            # Covers the call AND the consumption of its result: a model whose
            # rank() forgets to return leaves `proposed` as None, and iterating
            # None must degrade to rules like every other model failure.
            logger.error("model failed while ranking, serving rules: %s", err)
            return original

        if not result:
            # A model narrowing to nothing is indistinguishable from a model bug,
            # and serving a user zero exercises is worse than serving the rules
            # baseline -- which is already injury- and equipment-filtered. Log it
            # so the two cases can be told apart.
            logger.warning("model returned no usable candidates, serving rules")
            return original
        return result
