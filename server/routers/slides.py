from __future__ import annotations

import importlib
import json
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional

import cv2
import numpy as np
from fastapi import APIRouter, File, HTTPException, UploadFile, status
from pydantic import BaseModel

try:  # pragma: no cover - runtime dependency check
    _rapidfuzz_module = importlib.import_module("rapidfuzz.fuzz")
except ModuleNotFoundError as exc:  # pragma: no cover
    raise RuntimeError(
        "rapidfuzz is required but not installed. Run `pip install rapidfuzz`."
    ) from exc

token_sort_ratio = _rapidfuzz_module.token_sort_ratio

from server.core.clip_utils import embed_image, embed_text, cosine_np
from server.core.cv_detect import detect_and_crop_slide
from server.core.gemini import (
    GeminiError,
    answer_question_with_context,
    summarize_slide,
)
from server.core.image_utils import decode_image
from server.core.text_ocr import extract_text
from server.models.summary_schema import (
    BoundingBoxPoint,
    CompareSlidesResponse,
    GeminiSummary,
    ProcessSlideResponse,
    SlideComparisonMetrics,
    SlideVisualDetails,
)
from server.storage import (
    append_slide_history,
    load_last_state,
    load_slide_history,
    save_last_state,
)


logger = logging.getLogger(__name__)

router = APIRouter(tags=["slides"])


TEXT_THRESHOLD = float(os.getenv("TEXT_THRESHOLD", "0.60"))
CLIP_THRESHOLD = float(os.getenv("CLIP_THRESHOLD", "0.88"))
USE_BBOX_FOR_ANALYSIS = os.getenv("USE_BBOX", "0") == "1"
QUESTION_RELEVANCE_THRESHOLD = float(
    os.getenv("QUESTION_RELEVANCE_THRESHOLD", "0.20")
)
MAX_SLIDE_CONTEXT = int(os.getenv("SLIDE_CONTEXT_LIMIT", "5"))
MAX_CONVERSATION_MEMORY = int(os.getenv("CONVERSATION_MEMORY_LIMIT", "5"))

# Extremely small sets to keep obvious off-topic queries from being answered.
# Anything not matching these will be treated as related enough to proceed.
OFF_TOPIC_KEYWORDS = {
    "soccer",
    "football",
    "basketball",
    "baseball",
    "harry potter",
    "taylor swift",
    "celebrity",
    "movie",
    "music video",
    "recipe",
    "cook",
    "pizza",
    "burger",
    "weather",
    "vacation",
    "travel",
}

ACADEMIC_HINTS = {
    "activation",
    "algorithm",
    "analysis",
    "architecture",
    "classification",
    "function",
    "gradient",
    "graph",
    "lecture",
    "model",
    "neural",
    "network",
    "optimization",
    "probability",
    "regression",
    "statistics",
    "summary",
    "training",
}


_previous_text: Optional[str] = None
_previous_clip_vec: Optional[np.ndarray] = None
_state_initialized = False
_conversation_memory: List[dict[str, str]] = []


class QuestionRequest(BaseModel):
    question: str
    slide_summary: Optional[Dict[str, Any]] = None


def _corners_to_points(corners: Optional[np.ndarray]) -> Optional[List[BoundingBoxPoint]]:
    if corners is None:
        return None
    return [BoundingBoxPoint(x=int(point[0]), y=int(point[1])) for point in corners]


def _ensure_previous_state_loaded() -> None:
    global _state_initialized, _previous_clip_vec, _previous_text
    if _state_initialized:
        return
    state = load_last_state()
    _previous_text = state.text
    if state.clip_vector is not None:
        _previous_clip_vec = state.clip_vector.astype(np.float32)
    _state_initialized = True


def _record_conversation(question: str, answer: str, slide_number: int) -> None:
    _conversation_memory.append(
        {
            "question": question.strip(),
            "answer": answer.strip(),
            "slide_number": slide_number,
        }
    )
    if len(_conversation_memory) > MAX_CONVERSATION_MEMORY:
        del _conversation_memory[:-MAX_CONVERSATION_MEMORY]


def _build_conversation_text() -> str:
    if not _conversation_memory:
        return ""
    segments = []
    for turn in _conversation_memory[-MAX_CONVERSATION_MEMORY:]:
        segments.append(
            f"Slide {turn['slide_number']} - User: {turn['question']}\nAssistant: {turn['answer']}"
        )
    return "\n\n".join(segments)


def _topic_hint(summary: Optional[Dict[str, Any]]) -> str:
    if not summary:
        return ""
    titles = summary.get("title") if isinstance(summary, dict) else None
    if titles and isinstance(titles, list) and titles:
        return titles[0]
    summary_list = summary.get("summary") if isinstance(summary, dict) else None
    if summary_list and isinstance(summary_list, list) and summary_list:
        return summary_list[0][:80]
    return ""


def _build_slide_context(history: List[Dict[str, Any]], limit: int) -> str:
    if not history:
        return ""
    selected = history[-limit:]
    parts: List[str] = []
    for entry in selected:
        summary_blob = json.dumps(entry.get("summary", {}), ensure_ascii=False)
        parts.append(
            f"Slide {entry.get('slide_number', '?')} (captured at {entry.get('timestamp', 'unknown')}):\n{summary_blob}"
        )
    return "\n\n".join(parts)


def _append_slide_history_entry(
    summary: Dict[str, Any],
    *,
    text_similarity: Optional[float],
    clip_cosine: Optional[float],
) -> Dict[str, Any]:
    history = load_slide_history()
    slide_number = history[-1]["slide_number"] + 1 if history else 1
    entry = {
        "slide_number": slide_number,
        "timestamp": datetime.utcnow().isoformat(),
        "summary": summary,
        "metrics": {
            "text_similarity": text_similarity,
            "clip_cosine": clip_cosine,
        },
    }
    append_slide_history(entry)
    return entry


def _question_tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"\b[a-zA-Z][\w-]*\b", text.lower()) if token}


def _is_question_obviously_unrelated(question: str, summary: Dict[str, Any]) -> bool:
    """Return True only when the question is clearly unrelated to the slide."""
    question_tokens = _question_tokens(question)
    if not question_tokens:
        return False

    summary_text = json.dumps(summary or {}, ensure_ascii=False).lower()
    summary_tokens = _question_tokens(summary_text)

    # If we see any shared tokens or obvious academic hints, treat as related.
    if question_tokens & summary_tokens:
        return False
    if any(hint in question_tokens for hint in ACADEMIC_HINTS):
        return False

    # Otherwise only reject if we detect an explicit off-topic keyword.
    question_text = question.lower()
    return any(keyword in question_text for keyword in OFF_TOPIC_KEYWORDS)


@dataclass
class _SlideSample:
    analysis_image: np.ndarray
    clip_vector: np.ndarray
    ocr_text: str
    visual: SlideVisualDetails


def _process_frame(frame: np.ndarray) -> _SlideSample:
    cropped, detected, corners = detect_and_crop_slide(frame)
    analysis_region = cropped if detected and USE_BBOX_FOR_ANALYSIS else frame

    clip_tensor = embed_image(analysis_region)
    clip_vector = clip_tensor.detach().cpu().numpy()[0].astype(np.float32)

    ocr_text = extract_text(analysis_region)

    visual = SlideVisualDetails(
        slide_detected=detected,
        bounding_box=_corners_to_points(corners),
        cropped_image_base64=None,  # Bounding box previews disabled for now
        annotated_image_base64=None,
    )

    return _SlideSample(
        analysis_image=analysis_region,
        clip_vector=clip_vector,
        ocr_text=ocr_text,
        visual=visual,
    )


def _determine_change(
    current_text: str,
    current_clip: np.ndarray,
) -> tuple[bool, Optional[float], Optional[float]]:
    _ensure_previous_state_loaded()

    if _previous_text is None or _previous_clip_vec is None:
        return True, None, None

    text_similarity = token_sort_ratio(current_text, _previous_text) / 100.0
    clip_cosine = cosine_np(current_clip, _previous_clip_vec)
    is_new = text_similarity < TEXT_THRESHOLD and clip_cosine < CLIP_THRESHOLD
    return is_new, text_similarity, clip_cosine


def _update_memory(
    *,
    text: str,
    clip_vector: np.ndarray,
) -> None:
    global _previous_text, _previous_clip_vec
    _previous_text = text
    _previous_clip_vec = clip_vector


@router.post(
    "/process_slide",
    response_model=ProcessSlideResponse,
    summary="Process a slide image using CLIP and OCR similarity heuristics.",
)
async def process_slide(image: UploadFile = File(...)) -> ProcessSlideResponse:
    try:
        raw_bytes = await image.read()
        frame = decode_image(raw_bytes)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image file: {exc}",
        ) from exc

    sample = _process_frame(frame)
    is_new, text_similarity, clip_cosine = _determine_change(
        sample.ocr_text,
        sample.clip_vector,
    )

    summary_payload = None
    current_slide_number: Optional[int] = None

    if is_new:
        logger.info(
            "New slide detected (text=%.3f, clip=%.3f); invoking Gemini.",
            text_similarity if text_similarity is not None else -1.0,
            clip_cosine if clip_cosine is not None else -1.0,
        )
        try:
            summary_payload = summarize_slide(sample.analysis_image, ocr_text=sample.ocr_text)
        except GeminiError as exc:
            logger.error("Gemini summarization failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Gemini summarization failed: {exc}",
            ) from exc

        save_last_state(
            sample.analysis_image,
            summary=summary_payload,
            text=sample.ocr_text,
            clip_vector=sample.clip_vector,
        )
        _update_memory(text=sample.ocr_text, clip_vector=sample.clip_vector)

        if summary_payload is not None:
            history_entry = _append_slide_history_entry(
                summary_payload,
                text_similarity=text_similarity,
                clip_cosine=clip_cosine,
            )
            current_slide_number = history_entry["slide_number"]
        else:
            history = load_slide_history()
            current_slide_number = (history[-1]["slide_number"] + 1) if history else 1
    else:
        logger.info(
            "Slide unchanged (text=%.3f, clip=%.3f); reusing cached summary.",
            text_similarity if text_similarity is not None else -1.0,
            clip_cosine if clip_cosine is not None else -1.0,
        )
        state = load_last_state()
        summary_payload = state.summary
        if summary_payload is None:
            logger.debug("No cached summary found; skipping summary payload.")
        save_last_state(
            sample.analysis_image,
            summary=summary_payload,
            text=sample.ocr_text,
            clip_vector=sample.clip_vector,
        )
        _update_memory(text=sample.ocr_text, clip_vector=sample.clip_vector)
        history = load_slide_history()
        if history:
            current_slide_number = history[-1]["slide_number"]
        else:
            current_slide_number = 1

    summary_model = GeminiSummary.model_validate(summary_payload) if summary_payload else None

    return ProcessSlideResponse(
        new_slide=is_new,
        clip_cosine=clip_cosine if clip_cosine is not None else 0.0,
        text_similarity=text_similarity,
        slide_detected=sample.visual.slide_detected,
        bounding_box=sample.visual.bounding_box,
        summary=summary_model,
        slide_number=current_slide_number,
    )


@router.post(
    "/compare_slides",
    response_model=CompareSlidesResponse,
    summary="Compare two slide images using CLIP and OCR similarity heuristics.",
)
async def compare_slides(
    image1: UploadFile = File(...),
    image2: UploadFile = File(...),
) -> CompareSlidesResponse:
    try:
        frame1 = decode_image(await image1.read())
        frame2 = decode_image(await image2.read())
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image file: {exc}",
        ) from exc

    sample1 = _process_frame(frame1)
    sample2 = _process_frame(frame2)

    text_similarity = token_sort_ratio(sample1.ocr_text, sample2.ocr_text) / 100.0
    clip_cosine = cosine_np(sample1.clip_vector, sample2.clip_vector)
    new_slide = text_similarity < TEXT_THRESHOLD and clip_cosine < CLIP_THRESHOLD

    metrics = SlideComparisonMetrics(
        clip_cosine=clip_cosine,
        text_similarity=text_similarity,
    )

    return CompareSlidesResponse(
        slide1=sample1.visual,
        slide2=sample2.visual,
        metrics=metrics,
        new_slide=new_slide,
    )


@router.post(
    "/ask",
    summary="Answer a question using the stored slide context.",
)
async def ask_question(payload: QuestionRequest) -> dict[str, object]:
    question = payload.question.strip()
    if not question:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Question cannot be empty.",
        )

    history = load_slide_history()
    if not history:
        return {"answer": "I don't have any slide context yet."}

    current_entry = history[-1]
    slide_number = current_entry.get("slide_number", len(history))
    summary_blob: Dict[str, Any] = (
        payload.slide_summary or current_entry.get("summary", {}) or {}
    )

    try:
        question_vec = embed_text(question)
        summary_vec = embed_text(json.dumps(summary_blob, ensure_ascii=False))
        relevance = cosine_np(question_vec, summary_vec)
    except Exception as exc:  # pragma: no cover - embedding failure
        logger.error("Failed to compute relevance: %s", exc)
        relevance = 0.0

    if relevance < QUESTION_RELEVANCE_THRESHOLD:
        if _is_question_obviously_unrelated(question, summary_blob):
            topic = _topic_hint(summary_blob)
            hint = f" ({topic})" if topic else ""
            return {
                "answer": f"This question does not appear related to the lecture slide topic{hint}.",
                "slide_number": slide_number,
                "relevance": relevance,
            }
        else:
            logger.debug(
                "Treating low-relevance question as related (relevance=%.3f): %s",
                relevance,
                question,
            )

    context_text = _build_slide_context(history, MAX_SLIDE_CONTEXT)
    conversation_text = _build_conversation_text()

    try:
        answer = answer_question_with_context(
            question=question,
            context=context_text,
            conversation=conversation_text,
        )
    except GeminiError as exc:
        logger.error("Gemini conversation response failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to generate answer: {exc}",
        ) from exc

    _record_conversation(question, answer, slide_number)
    return {
        "answer": answer,
        "slide_number": slide_number,
        "relevance": relevance,
    }
