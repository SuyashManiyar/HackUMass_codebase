from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import cv2
import numpy as np

STORAGE_DIR = Path(__file__).resolve().parent
LAST_JSON_PATH = STORAGE_DIR / "last_slide.json"
LAST_IMAGE_PATH = STORAGE_DIR / "last_slide_img.jpg"
LAST_TEXT_PATH = STORAGE_DIR / "last_slide_text.txt"
LAST_CLIP_PATH = STORAGE_DIR / "last_slide_clip.npy"


@dataclass
class SlideState:
    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None
    text: Optional[str] = None
    clip_vector: Optional[np.ndarray] = None


def _ensure_storage_dir() -> None:
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)


def load_last_state() -> SlideState:
    """Load the last processed slide information from storage."""
    _ensure_storage_dir()

    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None
    text: Optional[str] = None
    clip_vector: Optional[np.ndarray] = None

    if LAST_JSON_PATH.exists():
        try:
            summary = json.loads(LAST_JSON_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            summary = None

    if LAST_TEXT_PATH.exists():
        text = LAST_TEXT_PATH.read_text(encoding="utf-8")

    if LAST_CLIP_PATH.exists():
        try:
            clip_vector = np.load(LAST_CLIP_PATH)
        except ValueError:
            clip_vector = None

    if LAST_IMAGE_PATH.exists():
        image_path = LAST_IMAGE_PATH

    return SlideState(
        summary=summary,
        image_path=image_path,
        text=text,
        clip_vector=clip_vector,
    )


def save_last_state(
    image: np.ndarray,
    *,
    summary: Optional[Dict[str, Any]],
    text: str,
    clip_vector: np.ndarray,
) -> None:
    """Persist the latest slide artifacts."""
    _ensure_storage_dir()

    LAST_TEXT_PATH.write_text(text, encoding="utf-8")
    np.save(LAST_CLIP_PATH, clip_vector)

    if summary is not None:
        LAST_JSON_PATH.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    success = cv2.imwrite(str(LAST_IMAGE_PATH), image)
    if not success:
        raise RuntimeError(f"Failed to save slide image to {LAST_IMAGE_PATH}")


