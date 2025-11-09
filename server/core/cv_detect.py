from __future__ import annotations

from pathlib import Path
from typing import Optional, Tuple

import cv2
import numpy as np

EXTRA_PAD = 30


def order_points(pts: np.ndarray) -> np.ndarray:
    """Sort 4-point contour in top-left, top-right, bottom-right, bottom-left order."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def _get_centroid(contour: np.ndarray) -> Tuple[Optional[int], Optional[int]]:
    """Calculate the center (centroid) of a contour."""
    if contour.shape == (4, 2):
        moments = cv2.moments(contour.reshape(4, 1, 2))
    else:
        moments = cv2.moments(contour)

    if moments["m00"] == 0:
        return None, None

    centroid_x = int(moments["m10"] / moments["m00"])
    centroid_y = int(moments["m01"] / moments["m00"])
    return centroid_x, centroid_y


def find_screen(frame: np.ndarray, last_corners: Optional[np.ndarray] = None) -> Optional[np.ndarray]:
    """Find the largest 4-sided contour (slide/screen) in the frame."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    adaptive_thresh = cv2.adaptiveThreshold(
        blurred,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        11,
        2,
    )
    v = np.median(blurred)
    lower = int(max(0, 0.7 * v))
    upper = int(min(255, 1.3 * v))
    canny_edged = cv2.Canny(blurred, lower, upper)
    edged = cv2.bitwise_or(canny_edged, adaptive_thresh)

    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    min_area = frame.shape[0] * frame.shape[1] * 0.01
    valid_candidates = []
    for contour in contours:
        if cv2.contourArea(contour) < min_area:
            continue
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approx) == 4:
            x, y, w, h = cv2.boundingRect(approx)
            aspect_ratio = float(w) / h if h > 0 else 0
            if 0.3 < aspect_ratio < 3.0:
                valid_candidates.append(approx)

    if not valid_candidates:
        return None

    best_candidate = None
    if last_corners is not None:
        last_cx, last_cy = _get_centroid(last_corners)
        min_dist = float("inf")
        for candidate in valid_candidates:
            candidate_cx, candidate_cy = _get_centroid(candidate)
            if candidate_cx is None:
                continue
            dist = np.hypot(candidate_cx - last_cx, candidate_cy - last_cy)
            if dist < min_dist:
                min_dist = dist
                best_candidate = candidate
        max_allowed_dist = frame.shape[1] / 4
        if min_dist > max_allowed_dist:
            best_candidate = None

    if best_candidate is None:
        valid_candidates = sorted(valid_candidates, key=cv2.contourArea, reverse=True)
        best_candidate = valid_candidates[0]

    return order_points(best_candidate.reshape(4, 2))


def extract_bbox_with_padding(frame: np.ndarray, corners: np.ndarray, pad: int = EXTRA_PAD) -> np.ndarray:
    """Extract bounding box with padding around detected corners."""
    x, y, w, h = cv2.boundingRect(corners.astype(int))
    x1 = max(x - pad, 0)
    y1 = max(y - pad, 0)
    x2 = min(x + w + pad, frame.shape[1])
    y2 = min(y + h + pad, frame.shape[0])
    return frame[y1:y2, x1:x2]


def detect_and_crop_slide(
    frame: np.ndarray, last_corners: Optional[np.ndarray] = None
) -> Tuple[np.ndarray, bool, Optional[np.ndarray]]:
    """Detect slide in frame and return cropped image and corners."""
    corners = find_screen(frame, last_corners=last_corners)
    if corners is None:
        return frame, False, None

    cropped = extract_bbox_with_padding(frame, corners, pad=EXTRA_PAD)
    return cropped, True, corners


def draw_bounding_box(frame: np.ndarray, corners: Optional[np.ndarray]) -> np.ndarray:
    """Draw bounding box on the frame and return annotated image."""
    if corners is None:
        return frame.copy()

    annotated = frame.copy()
    pts = corners.astype(int)
    cv2.polylines(annotated, [pts], isClosed=True, color=(0, 255, 0), thickness=3)

    for idx, pt in enumerate(pts):
        cv2.circle(annotated, tuple(pt), 8, (0, 0, 255), -1)
        cv2.putText(
            annotated,
            str(idx + 1),
            (pt[0] + 10, pt[1]),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
    return annotated


