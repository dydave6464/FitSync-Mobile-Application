"""The dish classifier at runtime: the JSON model file, /health and /classify-dish.

No MySQL and no ONNX file: the embedder is a fake that turns a photo's
average colour into a vector, opened through DishModel.load's hook.
"""
import base64
import io
import json

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from app import dish_model as dm
from app.config import Settings
from app.dish_embedders import CLASSIFIER_FILENAME, EMBEDDERS, Embedder
from app.main import create_app

SPEC = EMBEDDERS["clip-b32"]
CLASSES = ["sinigang", "tinola", "tapa"]
# Rows are classes; columns the fake embedding's red, green and blue.
COEF = [[8.0, -4.0, -4.0], [-4.0, 8.0, -4.0], [-4.0, -4.0, 8.0]]


def settings_for(model_dir):
    return Settings(db_host="127.0.0.1", db_port=3306, db_user="u", db_password="p",
                    db_name="fitsync_test", model_dir=str(model_dir))


def colour_run(x):
    channel = x[0].reshape(3, -1).mean(axis=1)
    return (channel - channel.min())[None, :].astype(np.float32)


def fake_open(path, spec):
    return Embedder(spec, colour_run)


def write_classifier(model_dir, edit=None, with_embedder=True):
    path = model_dir / CLASSIFIER_FILENAME
    dm.write_model(str(path), version="dish-lr-1-clip-b32", classes=CLASSES,
                   embedder_key="clip-b32", coef=np.array(COEF), intercept=np.zeros(3),
                   swap_at=0.8, choice_at=0.5, photos={"train": 150, "test": 30})
    if edit:
        data = json.loads(path.read_text())
        edit(data)
        path.write_text(json.dumps(data))
    if with_embedder:
        (model_dir / SPEC.filename).write_bytes(b"stand-in for the onnx file")


def photo(rgb, fmt="JPEG"):
    buf = io.BytesIO()
    Image.new("RGB", (64, 48), rgb).save(buf, fmt)
    return base64.b64encode(buf.getvalue()).decode()


def client_for(model_dir):
    model = dm.DishModel.load(str(model_dir), open_embedder=fake_open)
    return TestClient(create_app(settings_for(model_dir), dish_model=model)), model


# --- the model file ----------------------------------------------------------


def test_write_model_saves_plain_numbers_and_the_pinned_embedder(tmp_path):
    write_classifier(tmp_path)
    data = json.loads((tmp_path / CLASSIFIER_FILENAME).read_text())
    assert data["format"] == dm.FORMAT
    assert data["classes"] == CLASSES
    assert data["embedder"] == {"key": "clip-b32", "repo": SPEC.repo, "revision": SPEC.revision,
                                "path": SPEC.path, "sha256": SPEC.sha256}
    assert data["coef"] == COEF and data["intercept"] == [0.0, 0.0, 0.0]
    assert (data["swapAt"], data["choiceAt"]) == (0.8, 0.5)
    assert data["photos"] == {"train": 150, "test": 30}


def test_no_model_file_is_absent(tmp_path):
    model = dm.DishModel.load(str(tmp_path), open_embedder=fake_open)
    assert model.status == "absent" and not model.usable and model.version is None


def test_a_model_without_its_downloaded_embedder_is_absent(tmp_path):
    write_classifier(tmp_path, with_embedder=False)
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"


def test_an_unknown_or_changed_embedder_is_absent(tmp_path):
    write_classifier(tmp_path, edit=lambda d: d["embedder"].update(key="resnet"))
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"
    write_classifier(tmp_path, edit=lambda d: d["embedder"].update(sha256="0" * 64))
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"


def test_a_broken_model_file_is_absent(tmp_path):
    (tmp_path / CLASSIFIER_FILENAME).write_text("{not json")
    (tmp_path / SPEC.filename).write_bytes(b"x")
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"
    write_classifier(tmp_path, edit=lambda d: d.update(coef=d["coef"][:2]))
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"
    write_classifier(tmp_path, edit=lambda d: d.update(choiceAt=0.9))
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"
    write_classifier(tmp_path, edit=lambda d: d.update(format="something-else/1"))
    assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent"


def test_a_good_model_file_loads(tmp_path):
    write_classifier(tmp_path)
    model = dm.DishModel.load(str(tmp_path), open_embedder=fake_open)
    assert model.status == "loaded" and model.usable
    assert model.version == "dish-lr-1-clip-b32" and model.classes == CLASSES


# --- /health -------------------------------------------------------------------


def test_health_reports_the_dish_model(tmp_path):
    client, _ = client_for(tmp_path)
    assert client.get("/health").json()["dishModel"] == {"status": "absent", "version": None}
    write_classifier(tmp_path)
    client, _ = client_for(tmp_path)
    assert client.get("/health").json()["dishModel"] == {"status": "loaded",
                                                         "version": "dish-lr-1-clip-b32"}


def test_create_app_without_a_dish_model_loads_its_own(tmp_path):
    # Every other test file builds the app this way; with no model file the
    # service starts and says the dish model is absent.
    body = TestClient(create_app(settings_for(tmp_path))).get("/health").json()
    assert body["dishModel"] == {"status": "absent", "version": None}


# --- POST /classify-dish -------------------------------------------------------


def test_classify_dish_names_the_top_three_highest_first(tmp_path):
    write_classifier(tmp_path)
    client, _ = client_for(tmp_path)
    res = client.post("/classify-dish", json={"image": photo((230, 20, 20)), "mimeType": "image/jpeg"})
    assert res.status_code == 200
    body = res.json()
    assert body["model"] == "dish-lr-1-clip-b32"
    assert [d["dish"] for d in body["dishes"]][0] == "sinigang"
    probabilities = [d["probability"] for d in body["dishes"]]
    assert probabilities == sorted(probabilities, reverse=True) and len(probabilities) == 3
    assert abs(sum(probabilities) - 1.0) < 1e-3
    assert (body["swapAt"], body["choiceAt"]) == (0.8, 0.5)


def test_classify_dish_reads_png_too(tmp_path):
    write_classifier(tmp_path)
    client, _ = client_for(tmp_path)
    res = client.post("/classify-dish", json={"image": photo((20, 220, 30), "PNG"), "mimeType": "image/png"})
    assert res.status_code == 200 and res.json()["dishes"][0]["dish"] == "tinola"


def test_classify_dish_without_a_model_is_503(tmp_path):
    client, _ = client_for(tmp_path)
    res = client.post("/classify-dish", json={"image": photo((230, 20, 20)), "mimeType": "image/jpeg"})
    assert res.status_code == 503


def test_classify_dish_refuses_what_is_not_a_photo(tmp_path):
    write_classifier(tmp_path)
    client, _ = client_for(tmp_path)
    for image in ("@@@not base64@@@", base64.b64encode(b"hello").decode(),
                  base64.b64encode(b"\0" * 1_500_001).decode()):
        res = client.post("/classify-dish", json={"image": image, "mimeType": "image/jpeg"})
        assert res.status_code == 400, image[:20]
    res = client.post("/classify-dish", json={"image": photo((1, 2, 3)), "mimeType": "image/gif"})
    assert res.status_code == 422


def test_non_finite_weights_are_absent(tmp_path):
    def poison(key):
        def edit(d):
            d[key] = json.loads(json.dumps(d[key]))
            if key == "coef":
                d[key][0][0] = float("nan")
            else:
                d[key][1] = float("inf")
        return edit
    for key in ("coef", "intercept"):
        write_classifier(tmp_path, edit=poison(key))
        assert dm.DishModel.load(str(tmp_path), open_embedder=fake_open).status == "absent", key


def test_classify_dish_names_the_classes_the_model_knows(tmp_path):
    # Node lets the classifier act only on dishes it was trained on: a dish
    # dropped for too few photos is one it can never answer.
    write_classifier(tmp_path)
    client, _ = client_for(tmp_path)
    res = client.post("/classify-dish", json={"image": photo((230, 20, 20)), "mimeType": "image/jpeg"})
    assert res.status_code == 200 and res.json()["classes"] == CLASSES
