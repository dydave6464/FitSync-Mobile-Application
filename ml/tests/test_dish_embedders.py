"""The dish classifier's image models: photo preparation, output reduction, download.

Nothing is downloaded and no ONNX file is opened: Embedder takes the model's
run function, so a fake stands in for onnxruntime, and fetch() takes the
opener, so a fake stands in for the network.
"""
import hashlib
import io
import re
from dataclasses import replace

import numpy as np
import pytest
from PIL import Image

from app import dish_embedders as de
from app import fetch_dish_embedder as fetch


def jpeg(img, **save):
    buf = io.BytesIO()
    img.save(buf, "JPEG", **save)
    return buf.getvalue()


def test_every_embedder_is_pinned_and_known():
    assert set(de.EMBEDDERS) == {"clip-b32", "dinov2-small", "mobilenetv4-small"}
    for key, spec in de.EMBEDDERS.items():
        assert spec.key == key
        assert re.fullmatch(r"[0-9a-f]{40}", spec.revision)
        assert re.fullmatch(r"[0-9a-f]{64}", spec.sha256)
        assert spec.output in ("image_embeds", "cls_mean", "logits")
        assert spec.url == "https://huggingface.co/{}/resolve/{}/{}".format(
            spec.repo, spec.revision, spec.path)
        assert spec.filename == "dish-embedder-{}.onnx".format(key)


def test_preprocess_gives_one_normalised_224_square():
    spec = de.EMBEDDERS["dinov2-small"]
    x = de.preprocess(Image.new("RGB", (300, 200), (255, 0, 0)), spec)
    assert x.shape == (1, 3, 224, 224) and x.dtype == np.float32
    expected = [(1 - spec.mean[0]) / spec.std[0], (0 - spec.mean[1]) / spec.std[1],
                (0 - spec.mean[2]) / spec.std[2]]
    for c in range(3):
        assert np.allclose(x[0, c], expected[c], atol=1e-3)


def test_preprocess_keeps_the_centre_of_a_wide_photo():
    # CLIP's shortest edge is 224, so a 448x224 photo is not resized, only cropped
    # to its middle 224 columns: original columns 112-335.
    spec = de.EMBEDDERS["clip-b32"]
    img = Image.new("RGB", (448, 224), (0, 0, 0))
    img.paste((255, 255, 255), (224, 0, 448, 224))
    x = de.preprocess(img, spec)
    black = (0 - spec.mean[0]) / spec.std[0]
    white = (1 - spec.mean[0]) / spec.std[0]
    assert np.isclose(x[0, 0, 100, 0], black, atol=1e-3)
    assert np.isclose(x[0, 0, 100, 223], white, atol=1e-3)


def test_load_image_turns_a_photo_upright_by_its_exif():
    exif = Image.Exif()
    exif[0x0112] = 6  # shown rotated 90 degrees
    img = de.load_image(jpeg(Image.new("RGB", (40, 20), (10, 200, 10)), exif=exif))
    assert img.size == (20, 40) and img.mode == "RGB"


def test_load_image_flattens_transparency_onto_white():
    buf = io.BytesIO()
    Image.new("RGBA", (8, 8), (0, 0, 0, 0)).save(buf, "PNG")
    img = de.load_image(buf.getvalue())
    assert img.mode == "RGB" and img.getpixel((0, 0)) == (255, 255, 255)


def test_load_image_refuses_what_is_not_an_image():
    with pytest.raises(ValueError):
        de.load_image(b"\xff\xd8\xff not really a jpeg")
    with pytest.raises(ValueError):
        de.load_image(b"hello")


def test_reduce_output_cls_mean_puts_the_class_token_beside_the_mean_patch():
    out = np.array([[[3.0, 0.0], [0.0, 2.0], [0.0, 4.0]]], dtype=np.float32)  # (1, 1+2, 2)
    raw = np.array([3.0, 0.0, 0.0, 3.0])
    assert np.allclose(de.reduce_output(out, "cls_mean"), raw / np.linalg.norm(raw))


def test_reduce_output_is_unit_length_for_embeddings_and_logits():
    for kind in ("image_embeds", "logits"):
        v = de.reduce_output(np.array([[3.0, 4.0]], dtype=np.float32), kind)
        assert np.allclose(v, [0.6, 0.8])
    with pytest.raises(ValueError):
        de.reduce_output(np.zeros((1, 2)), "pooled")


def test_embedder_prepares_the_photo_and_reduces_the_output():
    seen = []

    def run(x):
        seen.append(x.shape)
        return np.array([[0.0, 2.0]], dtype=np.float32)

    v = de.Embedder(de.EMBEDDERS["clip-b32"], run).embed(
        jpeg(Image.new("RGB", (64, 48), (1, 2, 3))))
    assert seen == [(1, 3, 224, 224)]
    assert np.allclose(v, [0.0, 1.0])


def spec_with(content):
    return replace(de.EMBEDDERS["mobilenetv4-small"],
                   sha256=hashlib.sha256(content).hexdigest())


def opener_for(content, urls):
    def opener(url, timeout):
        urls.append(url)
        return io.BytesIO(content)
    return opener


def test_fetch_downloads_checks_and_then_leaves_a_good_file_alone(tmp_path):
    spec, urls = spec_with(b"model bytes"), []
    assert fetch.fetch(spec, str(tmp_path), opener_for(b"model bytes", urls)) == "downloaded"
    assert (tmp_path / spec.filename).read_bytes() == b"model bytes"
    assert urls == [spec.url]
    assert fetch.fetch(spec, str(tmp_path), opener_for(b"model bytes", urls)) == "present"
    assert len(urls) == 1


def test_fetch_refuses_a_download_with_the_wrong_checksum_and_keeps_nothing(tmp_path):
    spec = spec_with(b"expected")
    with pytest.raises(ValueError, match="checksum"):
        fetch.fetch(spec, str(tmp_path), opener_for(b"tampered", []))
    assert list(tmp_path.iterdir()) == []


def test_keys_to_fetch_takes_the_flags_or_reads_the_saved_classifier(tmp_path):
    assert fetch.keys_to_fetch(True, [], str(tmp_path)) == sorted(de.EMBEDDERS)
    assert fetch.keys_to_fetch(False, ["clip-b32"], str(tmp_path)) == ["clip-b32"]
    (tmp_path / de.CLASSIFIER_FILENAME).write_text('{"embedder": {"key": "dinov2-small"}}')
    assert fetch.keys_to_fetch(False, [], str(tmp_path)) == ["dinov2-small"]


def test_keys_to_fetch_without_a_classifier_or_with_an_unknown_key_says_what_to_do(tmp_path):
    with pytest.raises(SystemExit, match="--all"):
        fetch.keys_to_fetch(False, [], str(tmp_path))
    with pytest.raises(SystemExit, match="unknown"):
        fetch.keys_to_fetch(False, ["resnet"], str(tmp_path))
