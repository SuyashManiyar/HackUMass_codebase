from __future__ import annotations

import importlib
import logging
import os
from dataclasses import dataclass
from typing import List, Optional

import cv2
import numpy as np
from fastapi import APIRouter, File, HTTPException, UploadFile, status

try:  # pragma: no cover - runtime dependency check
    _rapidfuzz_module = importlib.import_module("rapidfuzz.fuzz")
except ModuleNotFoundError as exc:  # pragma: no cover
    raise RuntimeError(
        "rapidfuzz is required but not installed. Run `pip install rapidfuzz`."
    ) from exc

token_sort_ratio = _rapidfuzz_module.token_sort_ratio

from server.core.clip_utils import embed_image
from server.core.cv_detect import detect_and_crop_slide
from server.core.gemini import GeminiError, summarize_slide
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
from server.storage import load_last_state, save_last_state


logger = logging.getLogger(__name__)

router = APIRouter(tags=["slides"])


TEXT_THRESHOLD = float(os.getenv("TEXT_THRESHOLD", "0.60"))
CLIP_THRESHOLD = float(os.getenv("CLIP_THRESHOLD", "0.88"))
USE_BBOX_FOR_ANALYSIS = os.getenv("USE_BBOX", "0") == "1"


_previous_text: Optional[str] = None
_previous_clip_vec: Optional[np.ndarray] = None
_state_initialized = False


def _cosine_similarity(vec_a: np.ndarray, vec_b: np.ndarray) -> float:
    vec_a = vec_a.astype(np.float32)
    vec_b = vec_b.astype(np.float32)
    denom = (np.linalg.norm(vec_a) * np.linalg.norm(vec_b)) + 1e-12
    return float(np.clip(np.dot(vec_a, vec_b) / denom, -1.0, 1.0))


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
    clip_cosine = _cosine_similarity(current_clip, _previous_clip_vec)
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

    summary_model = GeminiSummary.model_validate(summary_payload) if summary_payload else None

    return ProcessSlideResponse(
        new_slide=is_new,
        clip_cosine=clip_cosine if clip_cosine is not None else 0.0,
        text_similarity=text_similarity,
        slide_detected=sample.visual.slide_detected,
        bounding_box=sample.visual.bounding_box,
        summary=summary_model,
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
    clip_cosine = _cosine_similarity(sample1.clip_vector, sample2.clip_vector)
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
