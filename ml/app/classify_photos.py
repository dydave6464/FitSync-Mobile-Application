"""Run the saved dish classifier over a folder of photos, for the evaluation.

    .venv/bin/python -m app.classify_photos --manifest SET.json --photos DIR --out PREDS.json [--split test]

SET.json holds {"photos": [{"file": ...}, ...]} -- both the 42-photo set and
dish-photos/manifest.json qualify. Writes {file: what /classify-dish would
answer}. No service and no database: it loads the model directory directly.
"""
import argparse
import json
import os
import sys

from app.dish_embedders import Embedder
from app.dish_model import DishModel

# Replaced in tests; the default opens the ONNX file.
open_embedder = Embedder.open


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Classify a folder of meal photos.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--photos", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--split", default=None, help="only rows with this split")
    parser.add_argument("--model-dir", default=os.environ.get("FITSYNC_MODEL_DIR", "models"))
    args = parser.parse_args(argv)
    model = DishModel.load(args.model_dir, open_embedder=open_embedder)
    if not model.usable:
        raise SystemExit("no usable dish classifier in {} (train it, then fetch its "
                         "embedder)".format(args.model_dir))
    with open(args.manifest) as f:
        rows = json.load(f)["photos"]
    if args.split:
        rows = [r for r in rows if r.get("split") == args.split]
    answers = {}
    for row in rows:
        with open(os.path.join(args.photos, row["file"]), "rb") as f:
            answers[row["file"]] = model.classify(f.read())
    with open(args.out, "w") as f:
        json.dump(answers, f, indent=1)
    print("{} photos -> {}".format(len(answers), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
