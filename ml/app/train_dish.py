"""Train the dish classifier (spec 2026-11-05-food-classifier, section 2).

    .venv/bin/python -m app.fetch_dish_embedder --all
    .venv/bin/python -m app.train_dish \\
        --photos /Users/davedev/claude/projects/docs/superpowers/dish-photos \\
        --exclude /Users/davedev/claude/projects/docs/superpowers/eval/photos

Reads <photos>/manifest.json: {"photos": [{"file", "dish", "split"}, ...]},
split "train" or "test". Drops training photos that are near-copies of a test
photo or of an --exclude photo (the 42-photo set is never trained on);
compares the embedders by 5-fold cross-validation on the training photos and
keeps the best (the smaller when within 2 points); sets the swap and choice
thresholds from the cross-validated predictions; fits on every training
photo; scores the held-out test photos once; writes
models/dish_classifier.json and reports/dish_classifier_cv.json.
"""
import argparse
import datetime
import json
import os
import sys
from dataclasses import dataclass
from typing import Dict, List, Sequence, Tuple

import numpy as np

from app.dish_embedders import CLASSIFIER_FILENAME, EMBEDDERS, Embedder
from app.dish_model import write_model

SEED = 20261105
FOLDS = 5
C_VALUES = (0.1, 1.0, 10.0)
NEAR_DUPLICATE = 0.95
SWAP_PRECISION = 0.90
CHOICE_PRECISION = 0.70
# A level must still cover this share of the photos to count.
MIN_SHARE = 0.10
MIN_TRAIN_PER_DISH = 20
TIE_POINTS = 0.02
DEDUPE_WITH = "dinov2-small"
NEVER = 1.01
VERSION = "dish-lr-1-{}"

# Replaced in tests; the default opens the ONNX file.
open_embedder = Embedder.open


@dataclass(frozen=True)
class Photo:
    file: str
    dish: str
    split: str


def read_manifest(photos_dir: str) -> List[Photo]:
    with open(os.path.join(photos_dir, "manifest.json")) as f:
        photos = [Photo(str(r["file"]), str(r["dish"]), str(r["split"]))
                  for r in json.load(f)["photos"]]
    bad = [p.file for p in photos if p.split not in ("train", "test")]
    if bad:
        raise SystemExit("split must be train or test: {}".format(", ".join(bad[:5])))
    return photos


def embed_files(embedder, paths: Sequence[str]) -> np.ndarray:
    vectors = []
    for path in paths:
        with open(path, "rb") as f:
            vectors.append(embedder.embed(f.read()))
    return np.vstack(vectors) if vectors else np.zeros((0, 1), dtype=np.float32)


def near_duplicates(train: np.ndarray, others: np.ndarray,
                    threshold: float = NEAR_DUPLICATE) -> List[int]:
    """Training rows whose cosine to any other row is >= threshold (rows are unit length)."""
    if len(train) == 0 or len(others) == 0:
        return []
    return [int(i) for i in np.where((train @ others.T).max(axis=1) >= threshold)[0]]


def build_classifier(c: float):
    from sklearn.linear_model import LogisticRegression

    return LogisticRegression(C=c, max_iter=2000)


def cross_validate(X: np.ndarray, y: np.ndarray, c_values=C_VALUES, folds: int = FOLDS,
                   seed: int = SEED) -> Tuple[float, float, np.ndarray]:
    """(best C, its accuracy, its out-of-fold probabilities, one column per class)."""
    from sklearn.model_selection import StratifiedKFold, cross_val_predict

    best = None
    for c in c_values:
        cv = StratifiedKFold(n_splits=folds, shuffle=True, random_state=seed)
        proba = cross_val_predict(build_classifier(c), X, y, cv=cv, method="predict_proba")
        accuracy = float((proba.argmax(axis=1) == y).mean())
        if best is None or accuracy > best[1]:
            best = (c, accuracy, proba)
    return best


def thresholds(proba: np.ndarray, y: np.ndarray, swap_precision: float = SWAP_PRECISION,
               choice_precision: float = CHOICE_PRECISION, min_share: float = MIN_SHARE):
    """The lowest top probability at which the classifier is right at least
    swap_precision (choice_precision) of the time, among levels still covering
    min_share of the photos; NEVER when no level does. (swap_at, choice_at, stats)."""
    confidence = proba.max(axis=1)
    correct = proba.argmax(axis=1) == y
    # Rounded down so a level never excludes the photo it came from.
    levels = sorted(set((np.floor(confidence * 1e4) / 1e4).tolist()))

    def lowest(target):
        for level in levels:
            chosen = confidence >= level
            share = float(chosen.mean())
            if share < min_share:
                break
            precision = float(correct[chosen].mean())
            if precision >= target:
                return level, round(precision, 4), round(share, 4)
        return NEVER, None, 0.0

    swap, choice = lowest(swap_precision), lowest(choice_precision)
    choice_at = min(choice[0], swap[0])
    stats = {"swapAt": swap[0], "swapPrecision": swap[1], "swapShare": swap[2],
             "choiceAt": choice_at, "choicePrecision": choice[1], "choiceShare": choice[2]}
    return swap[0], choice_at, stats


def pick(results: Dict[str, dict]) -> str:
    best = max(r["cvAccuracy"] for r in results.values())
    close = [k for k, r in results.items() if r["cvAccuracy"] >= best - TIE_POINTS - 1e-9]
    return min(close, key=lambda k: (EMBEDDERS[k].size_mb, -results[k]["cvAccuracy"]))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Train the dish classifier.")
    parser.add_argument("--photos", required=True)
    parser.add_argument("--exclude", default=None, help="photos never to train on (near-copies dropped)")
    parser.add_argument("--model-dir", default=os.environ.get("FITSYNC_MODEL_DIR", "models"))
    parser.add_argument("--report", default=os.path.join("reports", "dish_classifier_cv.json"))
    parser.add_argument("--embedders", default=",".join(sorted(EMBEDDERS)))
    parser.add_argument("--min-train", type=int, default=MIN_TRAIN_PER_DISH)
    args = parser.parse_args(argv)

    keys = [k for k in args.embedders.split(",") if k]
    unknown = [k for k in keys if k not in EMBEDDERS]
    if unknown:
        raise SystemExit("unknown embedder(s): " + ", ".join(unknown))
    photos = read_manifest(args.photos)
    classes = sorted({p.dish for p in photos})
    if len(classes) < 3:
        raise SystemExit("need at least 3 dishes, got {}".format(len(classes)))
    train = [p for p in photos if p.split == "train"]
    test = [p for p in photos if p.split == "test"]
    missing = [k for k in keys
               if not os.path.isfile(os.path.join(args.model_dir, EMBEDDERS[k].filename))]
    if missing:
        raise SystemExit("missing {}: run python -m app.fetch_dish_embedder --all".format(
            ", ".join(missing)))

    embedders = {k: open_embedder(os.path.join(args.model_dir, EMBEDDERS[k].filename), EMBEDDERS[k])
                 for k in keys}
    where = lambda p: os.path.join(args.photos, p.file)  # noqa: E731
    vectors = {k: (embed_files(e, [where(p) for p in train]), embed_files(e, [where(p) for p in test]))
               for k, e in embedders.items()}

    # Near-copies are judged once, with one model, so every candidate trains
    # on the same photos.
    judge = DEDUPE_WITH if DEDUPE_WITH in keys else keys[0]
    parts = [vectors[judge][1]] if test else []
    if args.exclude:
        names = sorted(f for f in os.listdir(args.exclude)
                       if f.lower().endswith((".jpg", ".jpeg", ".png")))
        if names:
            parts.append(embed_files(embedders[judge], [os.path.join(args.exclude, f) for f in names]))
    others = np.vstack(parts) if parts else np.zeros((0, 1), dtype=np.float32)
    dropped = set(near_duplicates(vectors[judge][0], others))
    keep = [i for i in range(len(train)) if i not in dropped]

    y_train = np.array([classes.index(train[i].dish) for i in keep])
    y_test = np.array([classes.index(p.dish) for p in test], dtype=int)
    counts = {d: {"train": int((y_train == i).sum()), "test": int((y_test == i).sum())}
              for i, d in enumerate(classes)}
    short = [d for d in classes if counts[d]["train"] < args.min_train]
    if short:
        raise SystemExit("too few training photos (< {}) for: {}".format(
            args.min_train, ", ".join(short)))

    results, oof = {}, {}
    for k in keys:
        c, accuracy, proba = cross_validate(vectors[k][0][keep], y_train)
        results[k] = {"cvAccuracy": round(accuracy, 4), "C": c, "sizeMb": EMBEDDERS[k].size_mb}
        oof[k] = proba
        print("{}: cross-validated accuracy {:.3f} (C={})".format(k, accuracy, c), flush=True)
    chosen = pick(results)
    swap_at, choice_at, stats = thresholds(oof[chosen], y_train)
    final = build_classifier(results[chosen]["C"]).fit(vectors[chosen][0][keep], y_train)

    confusion = np.zeros((len(classes), len(classes)), dtype=int)
    accuracy_test = None
    if test:
        predicted = final.predict_proba(vectors[chosen][1]).argmax(axis=1)
        for truth, guess in zip(y_test, predicted):
            confusion[truth, guess] += 1
        accuracy_test = round(float((predicted == y_test).mean()), 4)
    per_dish = {d: {"n": int(confusion[i].sum()),
                    "recall": round(float(confusion[i, i]) / max(1, int(confusion[i].sum())), 4)}
                for i, d in enumerate(classes)}

    version = VERSION.format(chosen)
    write_model(os.path.join(args.model_dir, CLASSIFIER_FILENAME), version=version,
                classes=classes, embedder_key=chosen, coef=final.coef_,
                intercept=final.intercept_, swap_at=swap_at, choice_at=choice_at,
                photos={"train": len(keep), "test": len(test)})
    report = {
        "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "version": version,
        "classes": classes,
        "photos": {"train": len(keep), "test": len(test), "droppedNearDuplicates": len(dropped),
                   "perDish": counts},
        "embedders": results,
        "chosen": chosen,
        "thresholds": stats,
        "test": {"accuracy": accuracy_test, "perDish": per_dish,
                 "confusion": {"labels": classes, "matrix": confusion.tolist()}},
    }
    os.makedirs(os.path.dirname(args.report) or ".", exist_ok=True)
    with open(args.report, "w") as f:
        json.dump(report, f, indent=1)
        f.write("\n")
    print("chosen {}: test accuracy {}, swap at {}, choice at {}".format(
        chosen, accuracy_test, swap_at, choice_at))
    return 0


if __name__ == "__main__":
    sys.exit(main())
