from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

import cv2
import numpy as np

STORAGE_DIR = Path(__file__).resolve().parent
LAST_TEXT_PATH = STORAGE_DIR / "last_ocr.txt"
LAST_JSON_PATH = STORAGE_DIR / "last_slide.json"
LAST_IMAGE_PATH = STORAGE_DIR / "last_slide_img.jpg"


@dataclass
class SlideState:
    text: str = ""
    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None


def _ensure_storage_dir() -> None:
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)


def load_last_state() -> SlideState:
    """Load the last processed slide information from storage."""
    _ensure_storage_dir()

    text = ""
    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None

    if LAST_TEXT_PATH.exists():
        text = LAST_TEXT_PATH.read_text(encoding="utf-8")

    if LAST_JSON_PATH.exists():
        try:
            summary = json.loads(LAST_JSON_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            summary = None

    if LAST_IMAGE_PATH.exists():
        image_path = LAST_IMAGE_PATH

    return SlideState(text=text, summary=summary, image_path=image_path)


def save_last_state(image: np.ndarray, text: str, summary: Dict[str, Any]) -> None:
    """Persist the latest slide image, OCR text, and summary."""
    _ensure_storage_dir()

    LAST_TEXT_PATH.write_text(text, encoding="utf-8")
    LAST_JSON_PATH.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    success = cv2.imwrite(str(LAST_IMAGE_PATH), image)
    if not success:
        raise RuntimeError(f"Failed to save slide image to {LAST_IMAGE_PATH}")


