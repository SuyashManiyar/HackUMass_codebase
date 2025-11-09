from __future__ import annotations

import re
from collections import Counter
from difflib import SequenceMatcher
from typing import Tuple


WORD_REGEX = re.compile(r"\b[\w'-]+\b", re.UNICODE)


def _tokenize(text: str) -> Counter:
    tokens = WORD_REGEX.findall(text.lower())
    return Counter(tokens)


def token_delta_ratio(previous: str, current: str) -> float:
    """
    Compute the proportion of tokens that changed between two strings.

    Returns a value in [0, 1], where 0 means identical token counts
    and 1 means completely different.
    """
    if not previous and not current:
        return 0.0

    prev_tokens = _tokenize(previous)
    curr_tokens = _tokenize(current)

    all_tokens = set(prev_tokens) | set(curr_tokens)
    total = 0
    diff = 0

    for token in all_tokens:
        prev_count = prev_tokens.get(token, 0)
        curr_count = curr_tokens.get(token, 0)
        total += max(prev_count, curr_count)
        diff += abs(prev_count - curr_count)

    if total == 0:
        return 0.0

    return diff / total


def similarity_scores(previous: str, current: str) -> Tuple[float, float]:
    """Return (sequence_similarity, token_delta) metrics."""
    seq_similarity = SequenceMatcher(None, previous, current).ratio()
    token_change = token_delta_ratio(previous, current)
    return seq_similarity, token_change


def evaluate_change(
    previous: str,
    current: str,
    *,
    ratio_threshold: float = 0.85,
    token_threshold: float = 0.2,
) -> Tuple[bool, float, float]:
    """
    Return (changed, seq_similarity, token_change) given two OCR strings.

    - If there is no previous text we treat it as a change.
    - Otherwise we compute both character-level similarity and token delta.
    """
    if not previous:
        return True, 0.0, 1.0

    seq_similarity, token_change = similarity_scores(previous, current)
    changed = seq_similarity < ratio_threshold or token_change > token_threshold
    return changed, seq_similarity, token_change


def is_slide_changed(
    previous: str,
    current: str,
    *,
    ratio_threshold: float = 0.85,
    token_threshold: float = 0.2,
) -> bool:
    """
    Decide if the slide content changed using character and token heuristics.
    """
    changed, _seq_similarity, _token_change = evaluate_change(
        previous,
        current,
        ratio_threshold=ratio_threshold,
        token_threshold=token_threshold,
    )
    return changed


