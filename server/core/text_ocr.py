from __future__ import annotations

from functools import lru_cache
from typing import Sequence

import easyocr
import numpy as np


DEFAULT_LANGUAGES: Sequence[str] = ("en",)


@lru_cache(maxsize=1)
def _get_reader(languages: tuple[str, ...] = DEFAULT_LANGUAGES) -> easyocr.Reader:
    """
    Lazily create and cache the EasyOCR reader.
    """
    return easyocr.Reader(list(languages))


def extract_text(
    image: np.ndarray,
    *,
    languages: Sequence[str] = DEFAULT_LANGUAGES,
) -> str:
    """
    Run OCR on the provided image and return normalized text.
    """
    reader = _get_reader(tuple(languages))
    results = reader.readtext(image, detail=0)
    lines = [line.strip() for line in results if line.strip()]
    return "\n".join(lines).strip()

