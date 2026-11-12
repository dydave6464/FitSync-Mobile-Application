"""Training the dish classifier: its parts, then end to end on tiny generated photos.

The fake embedder's vector is the photo's colour (the class signal) beside 64
numbers seeded by the photo's own pixels, so two photos of one dish are far from
near-copies (cosine about 0.25) while an exact copy is one (cosine 1).
"""
import hashlib
import json
import shutil

import numpy as np
import pytest
from PIL import Image

from app import classify_photos
from app import dish_model as dm
from app import train_dish as td
from app.dish_embedders import CLASSIFIER_FILENAME, EMBEDDERS, Embedder

COLOURS = {"sinigang": (220, 40, 40), "tinola": (40, 200, 60), "tapa": (50, 60, 210)}


def run_for(spec):
    def run(x):
        channel = x[0].reshape(3, -1).mean(axis=1)
        signal = 1.5 * (channel - channel.min())
        seed = int(hashlib.sha1(x.tobytes()).hexdigest()[:8], 16)
        noise = np.random.default_rng(seed).normal(size=64)
        v = np.concatenate([signal, noise]).astype(np.float32)
        return np.stack([v, v])[None] if spec.output == "cls_mean" else v[None]
    return run


def fake_open(path, spec):
    return Embedder(spec, run_for(spec))


# --- the parts ---------------------------------------------------------------


def test_near_duplicates_are_training_rows_too_close_to_another_photo():
    train = np.array([[1.0, 0.0], [0.0, 1.0]])
    other = np.array([[0.99, 0.141]]) / np.linalg.norm([0.99, 0.141])
    assert td.near_duplicates(train, other) == [0]
    assert td.near_duplicates(train, np.zeros((0, 2))) == []


def test_cross_validate_finds_separable_dishes():
    rng = np.random.default_rng(1)
    X = np.vstack([rng.normal(loc=c, scale=0.3, size=(30, 4)) for c in (0.0, 2.0, 4.0)])
    y = np.repeat([0, 1, 2], 30)
    c, accuracy, proba = td.cross_validate(X, y)
    assert c in td.C_VALUES and accuracy >= 0.95 and proba.shape == (90, 3)


def rows(conf, correct, n):
    """n probability rows whose top value is conf, right (class 0) or wrong (class 1)."""
    rest = (1 - conf) / 2
    row = [conf, rest, rest] if correct else [rest, conf, rest]
    return [row] * n


def test_thresholds_are_the_lowest_levels_that_reach_90_and_70_percent():
    proba = np.array(rows(0.9, True, 10) + rows(0.6, True, 3) + rows(0.6, False, 2)
                     + rows(0.4, True, 1) + rows(0.4, False, 4))
    y = np.zeros(len(proba), dtype=int)
    swap_at, choice_at, stats = td.thresholds(proba, y)
    # 0.4 and up: 14/20 right = 70 %; 0.6 and up: 13/15; 0.9 and up: 10/10.
    assert (swap_at, choice_at) == (0.9, 0.4)
    assert stats["swapPrecision"] == 1.0 and stats["swapShare"] == 0.5
    assert stats["choicePrecision"] == 0.7 and stats["choiceShare"] == 1.0


def test_thresholds_never_swap_when_too_few_photos_reach_the_level():
    proba = np.array(rows(0.99, True, 1) + rows(0.5, False, 19))
    swap_at, choice_at, _ = td.thresholds(proba, np.zeros(20, dtype=int))
    assert swap_at == td.NEVER and choice_at == td.NEVER


def test_pick_takes_the_smaller_model_within_two_points():
    sizes = {k: EMBEDDERS[k].size_mb for k in EMBEDDERS}
    assert sizes["mobilenetv4-small"] < sizes["dinov2-small"]
    assert td.pick({"dinov2-small": {"cvAccuracy": 0.90},
                    "mobilenetv4-small": {"cvAccuracy": 0.89}}) == "mobilenetv4-small"
    assert td.pick({"dinov2-small": {"cvAccuracy": 0.95},
                    "mobilenetv4-small": {"cvAccuracy": 0.90}}) == "dinov2-small"


# --- end to end --------------------------------------------------------------


def make_photo(path, rgb, jitter):
    rng = np.random.default_rng(jitter)
    shade = tuple(int(np.clip(c + rng.integers(-10, 11), 0, 255)) for c in rgb)
    Image.new("RGB", (32, 32), shade).save(path, "JPEG")


@pytest.fixture
def photos(tmp_path):
    folder = tmp_path / "dish-photos"
    folder.mkdir()
    rows_ = []
    n = 0
    for dish, rgb in COLOURS.items():
        for i in range(26):
            n += 1
            name = "{}-{:03d}.jpg".format(dish, i)
            make_photo(folder / name, rgb, n)
            rows_.append({"file": name, "dish": dish, "split": "test" if i < 4 else "train"})
    (folder / "manifest.json").write_text(json.dumps({"photos": rows_}))
    return folder


@pytest.fixture
def model_dir(tmp_path, monkeypatch):
    folder = tmp_path / "models"
    folder.mkdir()
    for spec in EMBEDDERS.values():
        (folder / spec.filename).write_bytes(b"stand-in")
    monkeypatch.setattr(td, "open_embedder", fake_open)
    monkeypatch.setattr(classify_photos, "open_embedder", fake_open)
    return folder


def test_training_end_to_end(tmp_path, photos, model_dir):
    exclude = tmp_path / "old-test-set"
    exclude.mkdir()
    shutil.copy(photos / "tapa-010.jpg", exclude / "c999.jpg")  # an exact copy of a training photo
    report = tmp_path / "report.json"

    assert td.main(["--photos", str(photos), "--exclude", str(exclude),
                    "--model-dir", str(model_dir), "--report", str(report)]) == 0

    body = json.loads(report.read_text())
    assert body["classes"] == sorted(COLOURS)
    assert body["photos"]["droppedNearDuplicates"] == 1
    # How many --exclude photos were compared, so a folder matching nothing shows.
    assert body["photos"]["excludeCompared"] == 1
    assert body["photos"]["train"] == 3 * 22 - 1 and body["photos"]["test"] == 12
    assert set(body["embedders"]) == set(EMBEDDERS)
    # Every fake embedder is as good as the others, so the smallest is kept.
    assert body["chosen"] == "mobilenetv4-small"
    assert body["test"]["accuracy"] >= 0.9
    t = body["thresholds"]
    assert 0.0 <= t["choiceAt"] <= t["swapAt"] <= td.NEVER

    model = dm.DishModel.load(str(model_dir), open_embedder=fake_open)
    assert model.status == "loaded" and model.version == "dish-lr-1-mobilenetv4-small"
    fresh = tmp_path / "fresh.jpg"
    make_photo(fresh, COLOURS["sinigang"], 999)
    assert model.classify(fresh.read_bytes())["dishes"][0]["dish"] == "sinigang"

    out = tmp_path / "preds.json"
    assert classify_photos.main(["--manifest", str(photos / "manifest.json"), "--photos", str(photos),
                                 "--split", "test", "--out", str(out),
                                 "--model-dir", str(model_dir)]) == 0
    preds = json.loads(out.read_text())
    assert len(preds) == 12 and preds["tinola-000.jpg"]["dishes"][0]["dish"] == "tinola"


def test_training_refuses_a_dish_with_too_few_photos(photos, model_dir, tmp_path):
    with pytest.raises(SystemExit, match="too few"):
        td.main(["--photos", str(photos), "--model-dir", str(model_dir),
                 "--report", str(tmp_path / "r.json"), "--min-train", "30"])


def test_training_says_to_fetch_the_models_first(photos, tmp_path, monkeypatch):
    monkeypatch.setattr(td, "open_embedder", fake_open)
    with pytest.raises(SystemExit, match="fetch_dish_embedder --all"):
        td.main(["--photos", str(photos), "--model-dir", str(tmp_path / "empty"),
                 "--report", str(tmp_path / "r.json")])


def test_training_reads_collects_layout_manifest_beside_a_photos_folder(tmp_path, photos, model_dir):
    # collect.py keeps dish-photos/manifest.json with the photos in dish-photos/photos/.
    root = tmp_path / "collected"
    root.mkdir()
    shutil.copytree(photos, root / "photos")
    (root / "photos" / "manifest.json").rename(root / "manifest.json")
    report = tmp_path / "report.json"

    assert td.main(["--manifest", str(root / "manifest.json"), "--photos", str(root / "photos"),
                    "--model-dir", str(model_dir), "--report", str(report)]) == 0
    body = json.loads(report.read_text())
    assert body["photos"]["train"] == 3 * 22 and body["photos"]["test"] == 12
    assert body["photos"]["excludeCompared"] == 0


def test_training_counts_the_plates_when_the_manifest_groups_photos(photos, model_dir, tmp_path):
    manifest = photos / "manifest.json"
    body = json.loads(manifest.read_text())
    for row in body["photos"]:
        if row["dish"] == "sinigang":
            # 26 photos of 13 plates, two angles each.
            row["group"] = "plate-{}".format(int(row["file"][-7:-4]) // 2)
    manifest.write_text(json.dumps(body))
    report = tmp_path / "report.json"

    assert td.main(["--photos", str(photos), "--model-dir", str(model_dir),
                    "--report", str(report)]) == 0
    per_dish = json.loads(report.read_text())["photos"]["perDish"]
    assert per_dish["sinigang"]["plates"] == 13
    assert per_dish["sinigang"]["train"] == 22 and per_dish["sinigang"]["test"] == 4
    assert "plates" not in per_dish["tinola"]
