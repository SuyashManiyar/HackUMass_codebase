from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np


def decode_image(data: bytes) -> np.ndarray:
    """Decode raw image bytes into a BGR numpy array."""
    np_data = np.frombuffer(data, np.uint8)
    image = cv2.imdecode(np_data, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Invalid image data or unsupported format.")
    return image


def save_image(path: Path, image: np.ndarray) -> None:
    """Persist an image to disk, creating parent directories as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    success = cv2.imwrite(str(path), image)
    if not success:
        raise RuntimeError(f"Failed to save image to {path}")


