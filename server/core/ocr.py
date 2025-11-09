from __future__ import annotations

from functools import lru_cache
from typing import List, Sequence

import easyocr
import numpy as np

DEFAULT_LANGS: Sequence[str] = ("en",)


@lru_cache(maxsize=1)
def _get_reader(languages: tuple[str, ...] = DEFAULT_LANGS) -> easyocr.Reader:
    """Lazily create and cache the EasyOCR reader."""
    return easyocr.Reader(list(languages))


def extract_text(image: np.ndarray, languages: Sequence[str] = DEFAULT_LANGS) -> str:
    """Run OCR on the provided image and return normalized text."""
    reader = _get_reader(tuple(languages))
    result: List[str] = reader.readtext(image, detail=0)
    normalized_lines = [line.strip() for line in result if line.strip()]
    return "\n".join(normalized_lines).strip()


