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


class ProcessSlideResponse(BaseModel):
    changed: bool
    summary: Optional[GeminiSummary] = None
    slide_detected: bool = True
    debug: Optional[Dict[str, Any]] = None


