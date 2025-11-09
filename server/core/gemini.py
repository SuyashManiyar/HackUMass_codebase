from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any, Dict, Optional

import cv2
from google import genai
from google.genai import types
import numpy as np


GEMINI_PROMPT = """
Analyze the provided image of a presentation slide. Your task is to extract, identify, and categorize all content on the slide and format it exclusively as a single JSON object.

Do not include any text, apologies, or explanations before or after the JSON code block. Your entire response must be only the valid JSON.

The JSON object must follow this precise structure and adhere to the rules for each key:

{
  "title": ["..."],
  "enumeration": ["...", "..."],
  "equation": ["...", "..."],
  "table": ["...", "..."],
  "image": ["...", "..."],
  "code": ["...", "..."],
  "slide_number": ["..."],
  "summary": ["..."]
}

Core Principle: No Invented Content

Your primary task is to be accurate.

DO NOT INVENT or GUESS content. If an element is not clearly and explicitly visible on the slide, you MUST use an empty array [] for that key.

DO NOT add placeholder text or "N/A". An empty array [] is the only correct way to represent missing content.

This applies to all keys. It is perfectly acceptable and expected to return {"slide_number": [], "equation": [], "table": [], ...} if those elements are not on the slide.

Key-Specific Instructions:

"title": An array containing the verbatim text of the main slide title. (Use [] if no title is present).

"enumeration": An array of strings, where each string is the verbatim text of one bullet point or numbered list item. (Use [] if no lists are present).

"equation": An array of strings, where each string is the verbatim text of one equation found on the slide. (Use [] if no equations are present).

"table": An array of strings. Each string must be a descriptive summary of a table's content and purpose. (Use [] if no tables are present).

Goal: Describe the table for someone who cannot see it.

Bad: "Sales data."

Good: "A table comparing Q1 and Q2 sales revenue across three different regions: North, South, and West, showing total units sold and percentage growth."

"image": An array of strings. Each string must be a descriptive summary of an image's content and its relevance to the slide. (Use [] if no images are present).

Goal: Explain what the image shows and why it's on the slide.

Bad: "Bar chart."

Good: "A bar chart illustrating the sharp decline in monthly user engagement from January to June."

"code": An array of strings. Each string must be a concise summary of what a code block does or represents (e.g., "A Python function that calculates the factorial of a number using recursion"). (Use [] if no code blocks are present).

"slide_number": An array containing the verbatim slide number. If no slide number is visible on the image, you MUST use an empty array []. Do not guess or invent a number.

"summary": An array containing a single string. This string must be a detailed, synthetic summary that explains the entire slide's content and purpose. (Use [] only if the slide is completely blank).

Example: "This slide defines the 'Quantum Entanglement' concept. It begins with a formal definition, lists three key properties of entangled particles, and presents a diagram (the EPR paradox) to visually explain how two particles can remain connected over a distance."

Crucial Rules:

All values must be arrays of strings, even if there is only one item (e.g., "title": ["Main Title"]) or zero items.

If any element is not present on the slide (e.g., there are no tables or equations), you must use an empty array [] for that key.
"""

DEFAULT_MODEL_NAME = "gemini-2.5-flash"
ENV_API_KEY_NAME = "GEMINI_API_KEY"
DEFAULT_FALLBACK_API_KEY = "AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0"


class GeminiError(Exception):
    """Raised when Gemini analysis fails."""


@lru_cache(maxsize=1)
def _get_client(api_key: Optional[str] = None) -> genai.Client:
    key = api_key or os.getenv(ENV_API_KEY_NAME) or DEFAULT_FALLBACK_API_KEY
    if not key:
        raise GeminiError("Gemini API key is not configured.")
    return genai.Client(api_key=key)


def _to_jpeg_bytes(image: np.ndarray) -> bytes:
    success, encoded = cv2.imencode(".jpg", image)
    if not success:
        raise GeminiError("Failed to encode slide image as JPEG.")
    return encoded.tobytes()


def summarize_slide(
    slide_image: np.ndarray,
    *,
    ocr_text: str | None = None,
    model: str = DEFAULT_MODEL_NAME,
    prompt: str = GEMINI_PROMPT,
    api_key: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Analyze the slide image with Gemini and return the parsed JSON response.

    Args:
        slide_image: Cropped slide image in BGR format.
        ocr_text: Optional OCR text to send as additional context.
        model: Gemini model name.
        prompt: Instruction prompt for the model.
        api_key: Optional explicit API key override.
    """
    client = _get_client(api_key)
    image_bytes = _to_jpeg_bytes(slide_image)

    contents: list[types.Part | str] = [
        types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg"),
        prompt,
    ]

    if ocr_text:
        contents.append(f"\nExtracted OCR text for reference:\n{ocr_text}")

    try:
        response = client.models.generate_content(model=model, contents=contents)
    except Exception as exc:  # noqa: BLE001 - want to map any gemini error
        raise GeminiError(f"Gemini API call failed: {exc}") from exc

    raw_text = response.text.strip()
    if raw_text.startswith("```json"):
        raw_text = raw_text.removeprefix("```json").strip(" `\n")
    elif raw_text.startswith("```"):
        raw_text = raw_text.removeprefix("```").strip(" `\n")

    try:
        return json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise GeminiError(f"Gemini response was not valid JSON: {exc}") from exc


