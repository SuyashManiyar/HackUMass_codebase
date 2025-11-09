from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class GeminiSummary(BaseModel):
    title: List[str] = Field(default_factory=list)
    enumeration: List[str] = Field(default_factory=list)
    equation: List[str] = Field(default_factory=list)
    table: List[str] = Field(default_factory=list)
    image: List[str] = Field(default_factory=list)
    code: List[str] = Field(default_factory=list)
    slide_number: List[str] = Field(default_factory=list)
    summary: List[str] = Field(default_factory=list)

    class Config:
        populate_by_name = True
        extra = "allow"


class BoundingBoxPoint(BaseModel):
    x: int
    y: int


class SlideComparisonDetails(BaseModel):
    slide_detected: bool
    bounding_box: Optional[List[BoundingBoxPoint]] = None
    cropped_image_base64: Optional[str] = None
    annotated_image_base64: Optional[str] = None
    ocr_text: str = ""
    ocr_char_count: int = 0
    ocr_word_count: int = 0


class CompareSlidesResponse(BaseModel):
    slide1: SlideComparisonDetails
    slide2: SlideComparisonDetails
    sequence_similarity: float
    token_delta: float
    ssim_score: float
    are_same_slide: bool
    changed: bool


class ProcessSlideResponse(BaseModel):
    changed: bool
    summary: Optional[GeminiSummary] = None
    slide_detected: bool = True
    debug: Optional[Dict[str, Any]] = None


