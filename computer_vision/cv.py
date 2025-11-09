import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
import time
import os
from datetime import datetime

# --- Constants ---
WARPED_WIDTH = 1000
WARPED_HEIGHT = 600

STABLE_SSIM_THRESHOLD = 0.95
NEW_SLIDE_SSIM_THRESHOLD = 0.8

EXTRA_PAD = 30   # extra pixels around the detected bbox


def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def get_centroid(contour):
    if contour.shape == (4, 2):
        M = cv2.moments(contour.reshape(4, 1, 2))
    else:
        M = cv2.moments(contour)
        
    if M["m00"] == 0:
        return None, None
    
    return int(M["m10"] / M["m00"]), int(M["m01"] / M["m00"])


def find_screen(frame, last_corners=None, debug=False):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    
    adaptive_thresh = cv2.adaptiveThreshold(
        blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
        cv2.THRESH_BINARY_INV, 11, 2
    )
    v = np.median(blurred)
    lower = int(max(0, 0.7 * v))
    upper = int(min(255, 1.3 * v))
    canny_edged = cv2.Canny(blurred, lower, upper)
    
    edged = cv2.bitwise_or(canny_edged, adaptive_thresh)
    
    contours, _ = cv2.findContours(edged.copy(), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return (None, edged) if debug else None

    min_area = frame.shape[0] * frame.shape[1] * 0.01
    valid_candidates = []
    
    for c in contours:
        if cv2.contourArea(c) < min_area:
            continue
            
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)
        
        if len(approx) == 4:
            x, y, w, h = cv2.boundingRect(approx)
            aspect_ratio = float(w) / h if h > 0 else 0
            if 0.3 < aspect_ratio < 3.0:
                valid_candidates.append(approx)

    if not valid_candidates:
        return (None, edged) if debug else None

    best_candidate = None
    
    if last_corners is not None:
        last_cX, last_cY = get_centroid(last_corners)
        
        min_dist = float('inf')
        
        for cand in valid_candidates:
            cand_cX, cand_cY = get_centroid(cand)
            if cand_cX is None:
                continue
                
            dist = np.sqrt((cand_cX - last_cX)**2 + (cand_cY - last_cY)**2)
            
            if dist < min_dist:
                min_dist = dist
                best_candidate = cand
        
        max_allowed_dist = frame.shape[1] / 4
        if min_dist > max_allowed_dist:
            best_candidate = None
    
    if best_candidate is None:
        valid_candidates = sorted(valid_candidates, key=cv2.contourArea, reverse=True)
        best_candidate = valid_candidates[0]
        
    result = best_candidate.reshape(4, 2)
    return (result, edged) if debug else result


def extract_bbox_with_padding(frame, corners, pad=30):
    """
    Extracts the bounding rectangle around the detected box
    with added padding around it.
    """
    x, y, w, h = cv2.boundingRect(corners.astype(int))

    # add padding
    x1 = max(x - pad, 0)
    y1 = max(y - pad, 0)
    x2 = min(x + w + pad, frame.shape[1])
    y2 = min(y + h + pad, frame.shape[0])

    cropped = frame[y1:y2, x1:x2]
    return cropped


# -------------------------------------------------------
# CREATE TIMESTAMPED FOLDER FOR THIS RUN
# -------------------------------------------------------
run_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_DIR = f"captured_slides_{run_timestamp}"
os.makedirs(OUTPUT_DIR, exist_ok=True)

SAVE_INTERVAL = 5  # seconds
last_capture_time = 0
capture_counter = 0
# -------------------------------------------------------

# --- Main Application Loop ---
cap = cv2.VideoCapture(0) 

last_stable_slide_gray = None
previous_warped_gray = None

while True:
    ret, frame = cap.read()
    if not ret:
        break
        
    corners, edged = find_screen(frame, debug=True)
    print(corners)
    
    if corners is None:
        cv2.imshow("Live Feed", frame)
        previous_warped_gray = None
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
        continue
        
    cv2.drawContours(frame, [corners.astype(int)], -1, (0, 255, 0), 2)
    cv2.imshow("Live Feed", frame)

    # ------------------------------------------------------------------
    # SAVE CROPPED BBOX REGION EVERY 5 SECONDS
    # ------------------------------------------------------------------
    current_time = time.time()
    if current_time - last_capture_time >= SAVE_INTERVAL:

        # Extract cropped image with extra padding
        cropped_img = extract_bbox_with_padding(frame, corners, pad=EXTRA_PAD)

        filename = os.path.join(
            OUTPUT_DIR,
            f"slide_capture_{capture_counter:05d}.jpg"
        )

        cv2.imwrite(filename, cropped_img)
        print(f"[{time.strftime('%H:%M:%S')}] Saved cropped bbox: {filename}")

        capture_counter += 1
        last_capture_time = current_time
    # ------------------------------------------------------------------

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()


