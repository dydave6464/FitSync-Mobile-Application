"""Pre-trained image models that turn a meal photo into a vector.

Spec 2026-11-05-food-classifier, section 2. Each is an ONNX export pinned to a
Hugging Face revision and checked by SHA-256 when app.fetch_dish_embedder
downloads it into the model directory (models/*.onnx is git-ignored).
Training (app.train_dish) and serving (app.dish_model) both go through
Embedder.embed, so a photo is prepared exactly the same way in both.
"""
import io
from dataclasses import dataclass
from typing import Callable, Dict, Tuple

import numpy as np
from PIL import Image, ImageOps

CLASSIFIER_FILENAME = "dish_classifier.json"
# Pillow refuses far larger images by itself; a meal photo is never near this.
MAX_PIXELS = 40_000_000

CLIP_MEAN = (0.48145466, 0.4578275, 0.40821073)
CLIP_STD = (0.26862954, 0.26130258, 0.27577711)
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


@dataclass(frozen=True)
class EmbedderSpec:
    key: str
    repo: str
    revision: str
    path: str
    sha256: str
    size_mb: float
    shortest_edge: int
    crop: int
    mean: Tuple[float, float, float]
    std: Tuple[float, float, float]
    # How the model's first output becomes one vector (reduce_output).
    output: str

    @property
    def filename(self) -> str:
        return "dish-embedder-{}.onnx".format(self.key)

    @property
    def url(self) -> str:
        return "https://huggingface.co/{}/resolve/{}/{}".format(
            self.repo, self.revision, self.path)


# Sizes, revisions and checksums checked against Hugging Face on 2026-11-05;
# each runs on onnxruntime 1.19.2 (the last for Python 3.9). Preparation
# follows each repo's preprocessor_config.json.
EMBEDDERS: Dict[str, EmbedderSpec] = {
    "clip-b32": EmbedderSpec(
        "clip-b32", "Xenova/clip-vit-base-patch32",
        "6b7c523703ae26e39be4b03774966f8571c7f523",
        "onnx/vision_model_quantized.onnx",
        "583fd1110a514667812fee7d684952aaf82a99b959760c8d7dca7e0ab9839299",
        89.1, 224, 224, CLIP_MEAN, CLIP_STD, "image_embeds"),
    "dinov2-small": EmbedderSpec(
        "dinov2-small", "Xenova/dinov2-small",
        "c2bb04a51fab207c420665f1946016107bffc701",
        "onnx/model.onnx",
        "83141175ec78b4ff9a2bb58a4c7c264ba0054d1c2e122e5a8114b79a8d4179ea",
        88.5, 256, 224, IMAGENET_MEAN, IMAGENET_STD, "cls_mean"),
    "mobilenetv4-small": EmbedderSpec(
        "mobilenetv4-small", "onnx-community/mobilenetv4_conv_small.e2400_r224_in1k",
        "3ba07f12712fa58fd6b3d661f9909c9e332c5005",
        "onnx/model.onnx",
        "ca5b8dbf490f54e83c5d72f787821565447ea94347935f6b834cf0a4af0e8d37",
        15.1, 256, 224, IMAGENET_MEAN, IMAGENET_STD, "logits"),
}


def load_image(data: bytes) -> Image.Image:
    """The photo upright (EXIF rotation) and in RGB. ValueError if it is not one."""
    try:
        img = Image.open(io.BytesIO(data))
        if img.width * img.height > MAX_PIXELS:
            raise ValueError("the photo is too large")
        img = ImageOps.exif_transpose(img)
        if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
            rgba = img.convert("RGBA")
            flat = Image.new("RGB", rgba.size, (255, 255, 255))
            flat.paste(rgba, mask=rgba.split()[-1])
            img = flat
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.load()
        return img
    except ValueError:
        raise
    except Exception as err:
        raise ValueError("not a readable image: {}".format(err))


def preprocess(img: Image.Image, spec: EmbedderSpec) -> np.ndarray:
    """(1, 3, crop, crop) float32: shortest edge to spec.shortest_edge (bicubic),
    centre crop, scaled to 0-1, normalised by the model's mean and std.

    Only the photo's part under the crop is resized, straight to crop x crop:
    the same pixels as resizing the whole photo first, but a thin photo
    (1x100000 is a few KB) never becomes a many-GB image on the way."""
    width, height = img.size
    scale = spec.shortest_edge / min(width, height)
    new_w = max(spec.crop, int(round(width * scale)))
    new_h = max(spec.crop, int(round(height * scale)))
    left = (new_w - spec.crop) // 2
    top = (new_h - spec.crop) // 2
    if (new_w, new_h) == (width, height):
        img = img.crop((left, top, left + spec.crop, top + spec.crop))
    else:
        # The crop window in the resized photo, mapped back onto the original.
        sx, sy = width / new_w, height / new_h
        box = (left * sx, top * sy, (left + spec.crop) * sx, (top + spec.crop) * sy)
        img = img.resize((spec.crop, spec.crop), Image.Resampling.BICUBIC, box=box)
    x = np.asarray(img, dtype=np.float32) / 255.0
    x = (x - np.asarray(spec.mean, dtype=np.float32)) / np.asarray(spec.std, dtype=np.float32)
    return np.ascontiguousarray(x.transpose(2, 0, 1)[None, ...], dtype=np.float32)


def reduce_output(output: np.ndarray, kind: str) -> np.ndarray:
    """One unit-length vector per photo from the model's first output."""
    if kind == "cls_mean":
        # (1, 1 + patches, d): the class token beside the mean patch token, the
        # usual way to read DINOv2 for a linear classifier.
        vector = np.concatenate([output[0, 0, :], output[0, 1:, :].mean(axis=0)])
    elif kind in ("image_embeds", "logits"):
        vector = output[0]
    else:
        raise ValueError("unknown output kind {!r}".format(kind))
    vector = np.asarray(vector, dtype=np.float32)
    norm = float(np.linalg.norm(vector))
    return vector / norm if norm > 0 else vector


class Embedder:
    """One image model. [run] takes the prepared (1,3,224,224) array and returns
    the model's first output; Embedder.open builds it from an ONNX file."""

    def __init__(self, spec: EmbedderSpec, run: Callable[[np.ndarray], np.ndarray]):
        self.spec = spec
        self._run = run

    @classmethod
    def open(cls, path: str, spec: EmbedderSpec) -> "Embedder":
        import onnxruntime as ort

        session = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        name = session.get_inputs()[0].name
        return cls(spec, lambda x: session.run(None, {name: x})[0])

    def embed(self, data: bytes) -> np.ndarray:
        return reduce_output(self._run(preprocess(load_image(data), self.spec)), self.spec.output)
