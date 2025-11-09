from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Tuple

import imagehash
import numpy as np
import open_clip
import torch
from PIL import Image


clip_model, _, _preprocess = open_clip.create_model_and_transforms(
    "ViT-B-32",
    pretrained="openai",
)
clip_model.eval()

_device = torch.device("cpu")
clip_model.to(_device)


def _preprocess_image(image: np.ndarray) -> torch.Tensor:
    image_pil = Image.fromarray(image[:, :, ::-1])
    return _preprocess(image_pil).unsqueeze(0)


def embed_image(image_np: np.ndarray) -> torch.Tensor:
    if image_np is None:
        raise ValueError("Image array is required to compute embeddings.")

    image_tensor = _preprocess_image(image_np).to(_device)
    with torch.no_grad():
        vec = clip_model.encode_image(image_tensor)
        vec = torch.nn.functional.normalize(vec, dim=-1)
    return vec.cpu()


def cosine_sim(vec1: torch.Tensor, vec2: torch.Tensor) -> float:
    if vec1.ndim != 2 or vec2.ndim != 2:
        raise ValueError("Vectors must be 2D tensors with shape [1, D].")
    return float(torch.matmul(vec1, vec2.T).item())


def compute_phash(image_np: np.ndarray) -> imagehash.ImageHash:
    image_pil = Image.fromarray(image_np[:, :, ::-1])
    return imagehash.phash(image_pil)


@dataclass
class SlideSimilarityResult:
    is_new: bool
    cosine_similarity: float
    phash_distance: Optional[int]


def is_new_slide(
    current_vec: torch.Tensor,
    current_phash: imagehash.ImageHash,
    previous_vec: Optional[torch.Tensor],
    previous_phash: Optional[imagehash.ImageHash],
    *,
    clip_thresh: float = 0.92,
    phash_max_dist: int = 10,
) -> SlideSimilarityResult:
    if previous_vec is None or previous_phash is None:
        return SlideSimilarityResult(is_new=True, cosine_similarity=0.0, phash_distance=None)

    cosine = cosine_sim(current_vec, previous_vec)
    phash_distance = previous_phash - current_phash

    clip_change = cosine < clip_thresh
    phash_change = phash_distance > phash_max_dist

    is_new = clip_change or phash_change
    return SlideSimilarityResult(
        is_new=is_new,
        cosine_similarity=cosine,
        phash_distance=phash_distance,
    )

