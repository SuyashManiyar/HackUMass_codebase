from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, File, HTTPException, UploadFile, status

from server.core.cv_detect import detect_and_crop_slide
from server.core.detect_change import evaluate_change
from server.core.gemini import GeminiError, summarize_slide
from server.core.image_utils import decode_image
from server.core.ocr import extract_text
from server.models.summary_schema import GeminiSummary, ProcessSlideResponse
from server.storage import load_last_state, save_last_state


logger = logging.getLogger(__name__)

router = APIRouter(tags=["slides"])


THRESHOLD = 0.85
TOKEN_THRESHOLD = 0.2
MIN_OCR_CHARS = 20
MIN_OCR_WORDS = 3


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


