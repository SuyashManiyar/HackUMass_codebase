from __future__ import annotations

import base64
import logging
from dataclasses import dataclass
from typing import Dict, List, Optional

import cv2
import numpy as np
from fastapi import APIRouter, File, HTTPException, UploadFile, status
from skimage.metrics import structural_similarity

from server.core.cv_detect import detect_and_crop_slide, draw_bounding_box
from server.core.detect_change import evaluate_change
from server.core.gemini import GeminiError, summarize_slide
from server.core.image_utils import decode_image
from server.core.ocr import extract_text
from server.models.summary_schema import (
    CompareSlidesResponse,
    GeminiSummary,
    ProcessSlideResponse,
    SlideComparisonDetails,
)
from server.storage import load_last_state, save_last_state


logger = logging.getLogger(__name__)

router = APIRouter(tags=["slides"])


THRESHOLD = 0.85
TOKEN_THRESHOLD = 0.2
MIN_OCR_CHARS = 20
MIN_OCR_WORDS = 3
SSIM_WIDTH = 1000
SSIM_HEIGHT = 600
SSIM_THRESHOLD = 0.6


@dataclass
class _SlideAnalysisInternal:
    payload: Dict[str, object]
    slide_image: np.ndarray
    ocr_text: str


def _encode_image_to_base64(image: np.ndarray) -> str:
    success, buffer = cv2.imencode(
        ".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), 85]
    )
    if not success:
        raise ValueError("Failed to encode image to JPEG.")
    return base64.b64encode(buffer).decode("utf-8")


def _corners_to_points(corners: Optional[np.ndarray]) -> Optional[List[Dict[str, int]]]:
    if corners is None:
        return None
    return [
        {"x": int(point[0]), "y": int(point[1])}
        for point in corners
    ]


def _resize_for_ssim(image: np.ndarray) -> np.ndarray:
    return cv2.resize(image, (SSIM_WIDTH, SSIM_HEIGHT))


def _compute_ssim(image_a: np.ndarray, image_b: np.ndarray) -> float:
    gray_a = cv2.cvtColor(image_a, cv2.COLOR_BGR2GRAY)
    gray_b = cv2.cvtColor(image_b, cv2.COLOR_BGR2GRAY)
    resized_a = _resize_for_ssim(gray_a)
    resized_b = _resize_for_ssim(gray_b)
    score = structural_similarity(resized_a, resized_b)
    return float(score)


async def _analyse_upload(file: UploadFile) -> _SlideAnalysisInternal:
    try:
        raw_bytes = await file.read()
        frame = decode_image(raw_bytes)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid image file: {exc}",
        ) from exc

    cropped, detected, corners = detect_and_crop_slide(frame)
    slide_image = cropped if detected else frame
    annotated = draw_bounding_box(frame, corners)

    ocr_text = extract_text(slide_image)
    char_count = len(ocr_text)
    word_count = len(ocr_text.split())

    payload: Dict[str, object] = {
        "slide_detected": detected,
        "bounding_box": _corners_to_points(corners),
        "cropped_image_base64": _encode_image_to_base64(slide_image),
        "annotated_image_base64": _encode_image_to_base64(annotated),
        "ocr_text": ocr_text,
        "ocr_char_count": char_count,
        "ocr_word_count": word_count,
    }

    return _SlideAnalysisInternal(
        payload=payload,
        slide_image=slide_image,
        ocr_text=ocr_text,
    )


@router.post(
    "/process_slide",
    response_model=ProcessSlideResponse,
    summary="Process a slide image and determine if it changed.",
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

    cropped, detected, _ = detect_and_crop_slide(frame)
    slide_image = cropped if detected else frame

    debug_info: dict[str, object] = {
        "slide_detected": detected,
    }

    if not detected:
        logger.info("No slide rectangle detected; skipping OCR and Gemini call.")
        last_state = load_last_state()
        summary_model = (
            GeminiSummary.model_validate(last_state.summary)
            if last_state.summary
            else None
        )
        debug_info["reason"] = "no_rectangle"
        return ProcessSlideResponse(
            changed=False,
            summary=summary_model,
            slide_detected=False,
            debug=debug_info,
        )

    ocr_text = extract_text(slide_image)
    char_count = len(ocr_text)
    word_count = len(ocr_text.split())
    debug_info.update(
        {
            "ocr_char_count": char_count,
            "ocr_word_count": word_count,
        }
    )

    if char_count < MIN_OCR_CHARS or word_count < MIN_OCR_WORDS:
        logger.info(
            "OCR text too short (chars=%s, words=%s); treating as unchanged.",
            char_count,
            word_count,
        )
        debug_info["reason"] = "insufficient_ocr_text"
        last_state = load_last_state()
        summary_model = (
            GeminiSummary.model_validate(last_state.summary)
            if last_state.summary
            else None
        )
        return ProcessSlideResponse(
            changed=False,
            summary=summary_model,
            slide_detected=True,
            debug=debug_info,
        )

    last_state = load_last_state()
    changed, seq_similarity, token_change = evaluate_change(
        last_state.text,
        ocr_text,
        ratio_threshold=THRESHOLD,
        token_threshold=TOKEN_THRESHOLD,
    )

    debug_info.update(
        {
            "sequence_similarity": seq_similarity,
            "token_delta": token_change,
            "ratio_threshold": THRESHOLD,
            "token_threshold": TOKEN_THRESHOLD,
            "previous_text_present": bool(last_state.text),
        }
    )

    summary_payload: Optional[dict] = last_state.summary
    if changed:
        logger.info(
            "New slide detected (similarity=%.3f, token_delta=%.3f); invoking Gemini.",
            seq_similarity,
            token_change,
        )
        try:
            summary_payload = summarize_slide(slide_image, ocr_text=ocr_text)
        except GeminiError as exc:
            logger.error("Gemini summarization failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Gemini summarization failed: {exc}",
            ) from exc

        save_last_state(slide_image, ocr_text, summary_payload)
        debug_info["reason"] = "new_slide"
    else:
        logger.info(
            "Slide unchanged (similarity=%.3f, token_delta=%.3f); reusing cached summary.",
            seq_similarity,
            token_change,
        )
        debug_info["reason"] = "similar_text"

    summary_model = GeminiSummary.model_validate(summary_payload) if summary_payload else None
    return ProcessSlideResponse(
        changed=changed,
        summary=summary_model,
        slide_detected=True,
        debug=debug_info,
    )


@router.post(
    "/compare_slides",
    response_model=CompareSlidesResponse,
    summary="Compare two slide images and report similarity metrics.",
)
async def compare_slides(
    image1: UploadFile = File(...),
    image2: UploadFile = File(...),
) -> CompareSlidesResponse:
    analysis1 = await _analyse_upload(image1)
    analysis2 = await _analyse_upload(image2)

    try:
        ssim_score = _compute_ssim(analysis1.slide_image, analysis2.slide_image)
    except cv2.error as exc:
        logger.error("Failed to compute SSIM: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to compute similarity score.",
        ) from exc

    changed, seq_similarity, token_delta = evaluate_change(
        analysis1.ocr_text,
        analysis2.ocr_text,
        ratio_threshold=THRESHOLD,
        token_threshold=TOKEN_THRESHOLD,
    )

    return CompareSlidesResponse(
        slide1=SlideComparisonDetails(**analysis1.payload),
        slide2=SlideComparisonDetails(**analysis2.payload),
        sequence_similarity=seq_similarity,
        token_delta=token_delta,
        ssim_score=ssim_score,
        are_same_slide=ssim_score >= SSIM_THRESHOLD,
        changed=changed,
    )


