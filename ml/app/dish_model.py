"""The dish classifier at runtime (spec 2026-11-05-food-classifier, sections 2-3).

A scikit-learn logistic regression over one pre-trained image model's vector,
saved by app.train_dish as plain JSON (models/dish_classifier.json, committed:
numbers only, no photos, no pickle to load). The image model itself
(models/dish-embedder-<key>.onnx, git-ignored) comes from
app.fetch_dish_embedder. With either missing the classifier is absent and
/classify-dish answers 503, which Node takes as "no second opinion".
"""
import base64
import binascii
import json
import logging
import os
from typing import Any, Callable, Dict, List, Optional

import numpy as np

from app.dish_embedders import CLASSIFIER_FILENAME, EMBEDDERS, Embedder

logger = logging.getLogger(__name__)

FORMAT = "fitsync-dish-classifier/1"
TOP = 3
MAX_PHOTO_BYTES = 1_500_000


def write_model(path: str, *, version: str, classes: List[str], embedder_key: str,
                coef, intercept, swap_at: float, choice_at: float,
                photos: Dict[str, int], outside_swap_at: Optional[float] = None) -> None:
    spec = EMBEDDERS[embedder_key]
    payload = {
        "format": FORMAT,
        "version": version,
        "classes": list(classes),
        "embedder": {"key": spec.key, "repo": spec.repo, "revision": spec.revision,
                     "path": spec.path, "sha256": spec.sha256},
        "coef": np.round(np.asarray(coef, dtype=np.float64), 6).tolist(),
        "intercept": np.round(np.asarray(intercept, dtype=np.float64), 6).tolist(),
        "swapAt": float(swap_at),
        "choiceAt": float(choice_at),
        "photos": dict(photos),
    }
    # Round 2's bar for a dish the AI named outside the 12 (spec 2026-11-12,
    # section 2). A round-1 file has none, and Node then leaves those alone.
    if outside_swap_at is not None:
        payload["outsideSwapAt"] = float(outside_swap_at)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f, indent=1)
        f.write("\n")


def decode_photo(image: str) -> bytes:
    """The photo's bytes. ValueError for anything Node should already have refused."""
    try:
        data = base64.b64decode(image, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("image must be base64")
    if not data:
        raise ValueError("image is empty")
    if len(data) > MAX_PHOTO_BYTES:
        raise ValueError("the photo must be at most 1.5 MB")
    return data


def _softmax(z: np.ndarray) -> np.ndarray:
    e = np.exp(z - z.max())
    return e / e.sum()


class DishModel:
    """The loaded classifier, or its absence. status is what /health reports."""

    def __init__(self, status: str, version: Optional[str] = None,
                 classes: Optional[List[str]] = None, coef: Optional[np.ndarray] = None,
                 intercept: Optional[np.ndarray] = None, embedder: Optional[Embedder] = None,
                 swap_at: Optional[float] = None, choice_at: Optional[float] = None,
                 outside_swap_at: Optional[float] = None):
        self.status = status
        self.version = version
        self.classes = classes or []
        self._coef = coef
        self._intercept = intercept
        self._embedder = embedder
        self.swap_at = swap_at
        self.choice_at = choice_at
        self.outside_swap_at = outside_swap_at

    @classmethod
    def load(cls, model_dir: str,
             open_embedder: Callable[[str, Any], Embedder] = Embedder.open) -> "DishModel":
        """The model if its JSON and its image model are both there and sound.

        A missing JSON is a fresh checkout before training, a missing image
        model one that has not run app.fetch_dish_embedder yet; anything
        unreadable is logged. Each is "absent": Snap a meal then keeps the
        vision AI's answer as it is, so none of them may stop the service.
        """
        path = os.path.join(model_dir, CLASSIFIER_FILENAME)
        if not os.path.isfile(path):
            return cls(status="absent")
        try:
            with open(path) as f:
                data = json.load(f)
            if data.get("format") != FORMAT:
                raise ValueError("format {!r}, expected {!r}".format(data.get("format"), FORMAT))
            saved = data.get("embedder") or {}
            spec = EMBEDDERS.get(saved.get("key"))
            if spec is None or saved.get("sha256") != spec.sha256:
                raise ValueError("embedder {!r} is not one this code knows".format(saved.get("key")))
            classes = [str(c) for c in data["classes"]]
            coef = np.asarray(data["coef"], dtype=np.float32)
            intercept = np.asarray(data["intercept"], dtype=np.float32)
            if (len(classes) < 2 or len(set(classes)) != len(classes) or coef.ndim != 2
                    or coef.shape[0] != len(classes) or intercept.shape != (len(classes),)):
                raise ValueError("weights do not match the {} classes".format(len(classes)))
            if not (np.isfinite(coef).all() and np.isfinite(intercept).all()):
                # Would load, then answer every photo with a 500.
                raise ValueError("weights are not all finite numbers")
            swap_at, choice_at = float(data["swapAt"]), float(data["choiceAt"])
            if not 0.0 <= choice_at <= swap_at <= 1.01:
                raise ValueError("thresholds out of order: choiceAt {} swapAt {}".format(
                    choice_at, swap_at))
            outside = data.get("outsideSwapAt")
            outside_swap_at = None
            if outside is not None:
                if isinstance(outside, bool) or not isinstance(outside, (int, float)):
                    raise ValueError("outsideSwapAt {!r} is not a number".format(outside))
                outside_swap_at = float(outside)
                if not swap_at <= outside_swap_at <= 1.01:
                    raise ValueError("thresholds out of order: swapAt {} outsideSwapAt {}".format(
                        swap_at, outside_swap_at))
            embedder_path = os.path.join(model_dir, spec.filename)
            if not os.path.isfile(embedder_path):
                logger.warning("dish classifier %s needs %s: run python -m app.fetch_dish_embedder",
                               path, spec.filename)
                return cls(status="absent")
            return cls(status="loaded", version=str(data["version"]), classes=classes,
                       coef=coef, intercept=intercept,
                       embedder=open_embedder(embedder_path, spec),
                       swap_at=swap_at, choice_at=choice_at,
                       outside_swap_at=outside_swap_at)
        except Exception as err:
            logger.error("dish classifier at %s is unusable: %s", path, err)
            return cls(status="absent")

    @property
    def usable(self) -> bool:
        return self.status == "loaded" and self._embedder is not None

    def probabilities(self, vector: np.ndarray) -> np.ndarray:
        if vector.shape != (self._coef.shape[1],):
            # The model's fault, not the photo's: a 500, never a 400.
            raise RuntimeError("embedding shape {}, the model expects {} values".format(
                vector.shape, self._coef.shape[1]))
        return _softmax(self._coef @ vector + self._intercept)

    def classify(self, photo: bytes) -> Dict[str, Any]:
        """The top 3 dishes for a photo, and every dish the model knows: Node
        lets it act only on those (a dish dropped from training is never one
        it can answer). ValueError when it is not a readable image."""
        p = self.probabilities(self._embedder.embed(photo))
        order = np.argsort(-p)[:TOP]
        return {
            "model": self.version,
            "dishes": [{"dish": self.classes[i], "probability": round(float(p[i]), 4)}
                       for i in order],
            "swapAt": self.swap_at,
            "choiceAt": self.choice_at,
            "outsideSwapAt": self.outside_swap_at,
            "classes": list(self.classes),
        }
