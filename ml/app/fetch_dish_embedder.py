"""Download the dish classifier's image model into the model directory.

    .venv/bin/python -m app.fetch_dish_embedder          # the one models/dish_classifier.json names
    .venv/bin/python -m app.fetch_dish_embedder --all    # all three candidates, to train

Each file comes from a pinned Hugging Face revision and must match its
SHA-256 (app/dish_embedders.py) before it is kept; a partial or wrong
download is deleted. models/*.onnx is git-ignored.
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
from typing import List

from app.dish_embedders import CLASSIFIER_FILENAME, EMBEDDERS

CHUNK = 1 << 20


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(spec, model_dir: str, opener=urllib.request.urlopen) -> str:
    """'present' when a good copy is already there, else 'downloaded'.
    Raises ValueError on a checksum mismatch, leaving nothing behind."""
    dest = os.path.join(model_dir, spec.filename)
    if os.path.isfile(dest) and sha256_of(dest) == spec.sha256:
        return "present"
    os.makedirs(model_dir, exist_ok=True)
    fd, part = tempfile.mkstemp(dir=model_dir, suffix=".part")
    try:
        with os.fdopen(fd, "wb") as out, opener(spec.url, timeout=60) as res:
            for block in iter(lambda: res.read(CHUNK), b""):
                out.write(block)
        got = sha256_of(part)
        if got != spec.sha256:
            raise ValueError("checksum mismatch for {}: expected {}, got {}".format(
                spec.key, spec.sha256, got))
        os.replace(part, dest)
        return "downloaded"
    finally:
        if os.path.exists(part):
            os.remove(part)


def keys_to_fetch(all_: bool, keys: List[str], model_dir: str) -> List[str]:
    if all_:
        return sorted(EMBEDDERS)
    if keys:
        unknown = [k for k in keys if k not in EMBEDDERS]
        if unknown:
            raise SystemExit("unknown embedder(s): {}; known: {}".format(
                ", ".join(unknown), ", ".join(sorted(EMBEDDERS))))
        return list(keys)
    path = os.path.join(model_dir, CLASSIFIER_FILENAME)
    if not os.path.isfile(path):
        raise SystemExit("no {} in {}: train one first, or pass --all to fetch every "
                         "candidate".format(CLASSIFIER_FILENAME, model_dir))
    with open(path) as f:
        return [json.load(f)["embedder"]["key"]]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Download the dish classifier's image model.")
    parser.add_argument("--all", action="store_true", help="every candidate (to train)")
    parser.add_argument("--key", action="append", default=[], help="one embedder; repeatable")
    parser.add_argument("--model-dir", default=os.environ.get("FITSYNC_MODEL_DIR", "models"))
    args = parser.parse_args(argv)
    for key in keys_to_fetch(args.all, args.key, args.model_dir):
        spec = EMBEDDERS[key]
        print("{}: {} ({:.0f} MB)".format(key, spec.url, spec.size_mb), flush=True)
        print("{}: {}".format(key, fetch(spec, args.model_dir)), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
