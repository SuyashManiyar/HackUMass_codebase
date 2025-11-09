from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import cv2
import numpy as np

STORAGE_DIR = Path(__file__).resolve().parent
LAST_JSON_PATH = STORAGE_DIR / "last_slide.json"
LAST_IMAGE_PATH = STORAGE_DIR / "last_slide_img.jpg"
LAST_TEXT_PATH = STORAGE_DIR / "last_slide_text.txt"
LAST_CLIP_PATH = STORAGE_DIR / "last_slide_clip.npy"
SLIDES_LOG_PATH = STORAGE_DIR / "slides_log.json"


@dataclass
class SlideState:
    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None
    text: Optional[str] = None
    clip_vector: Optional[np.ndarray] = None


def _ensure_storage_dir() -> None:
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)


def _load_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def load_last_state() -> SlideState:
    """Load the last processed slide information from storage."""
    _ensure_storage_dir()

    summary: Optional[Dict[str, Any]] = None
    image_path: Optional[Path] = None
    text: Optional[str] = None
    clip_vector: Optional[np.ndarray] = None

    if LAST_JSON_PATH.exists():
        summary = _load_json_file(LAST_JSON_PATH, None)

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


def load_slide_history(limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """Return the stored slide history, optionally truncated to the last [limit] entries."""
    _ensure_storage_dir()
    history: List[Dict[str, Any]] = _load_json_file(SLIDES_LOG_PATH, default=[])
    if limit is not None and limit > 0:
        return history[-limit:]
    return history


def append_slide_history(entry: Dict[str, Any]) -> None:
    """Append a new slide entry to the history log."""
    _ensure_storage_dir()
    history = load_slide_history()
    history.append(entry)
    SLIDES_LOG_PATH.write_text(
        json.dumps(history, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def reset_slide_history() -> None:
    """Remove the stored slide history."""
    if SLIDES_LOG_PATH.exists():
        SLIDES_LOG_PATH.unlink()


