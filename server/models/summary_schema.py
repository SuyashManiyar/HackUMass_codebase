from __future__ import annotations

from typing import List, Optional

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


class SlideVisualDetails(BaseModel):
    slide_detected: bool
    bounding_box: Optional[List[BoundingBoxPoint]] = None
    cropped_image_base64: Optional[str] = None
    annotated_image_base64: Optional[str] = None


class SlideComparisonMetrics(BaseModel):
    clip_cosine: float
    text_similarity: Optional[float] = None


class CompareSlidesResponse(BaseModel):
    slide1: SlideVisualDetails
    slide2: SlideVisualDetails
    metrics: SlideComparisonMetrics
    new_slide: bool


class ProcessSlideResponse(BaseModel):
    new_slide: bool
    clip_cosine: float
    text_similarity: Optional[float] = None
    slide_detected: bool
    bounding_box: Optional[List[BoundingBoxPoint]] = None
    summary: Optional[GeminiSummary] = None


