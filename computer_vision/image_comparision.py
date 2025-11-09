import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
import os
from datetime import datetime
import glob
import easyocr
from difflib import SequenceMatcher
import ssl
import certifi

# Fix SSL certificate verification
ssl._create_default_https_context = ssl._create_unverified_context

# --- Constants ---
WARPED_WIDTH = 1000
WARPED_HEIGHT = 600
EXTRA_PAD = 30   # extra pixels around the detected bbox

# -------------------------------
# Slide detection / utility functions
# -------------------------------
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

def find_screen(frame, last_corners=None):
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
        return None

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
        return None

    best_candidate = None
    if last_corners is not None:
        last_cX, last_cY = get_centroid(last_corners)
        min_dist = float('inf')
        for cand in valid_candidates:
            cand_cX, cand_cY = get_centroid(cand)
            if cand_cX is None:
                continue
            dist = np.hypot(cand_cX - last_cX, cand_cY - last_cY)
            if dist < min_dist:
                min_dist = dist
                best_candidate = cand
        max_allowed_dist = frame.shape[1] / 4
        if min_dist > max_allowed_dist:
            best_candidate = None

    if best_candidate is None:
        valid_candidates = sorted(valid_candidates, key=cv2.contourArea, reverse=True)
        best_candidate = valid_candidates[0]

    return order_points(best_candidate.reshape(4, 2))

def extract_bbox_with_padding(frame, corners, pad=30):
    x, y, w, h = cv2.boundingRect(corners.astype(int))
    x1 = max(x - pad, 0)
    y1 = max(y - pad, 0)
    x2 = min(x + w + pad, frame.shape[1])
    y2 = min(y + h + pad, frame.shape[0])
    return frame[y1:y2, x1:x2]

def preprocess_gray(img):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.resize(g, (WARPED_WIDTH, WARPED_HEIGHT))
    return g

def extract_text_ocr(img, reader):
    """Extract text from image using EasyOCR"""
    results = reader.readtext(img)
    text = ' '.join([result[1] for result in results])
    return text.strip()

def calculate_text_similarity(text1, text2):
    """Calculate character-level similarity between two texts"""
    if not text1 and not text2:
        return 1.0
    if not text1 or not text2:
        return 0.0
    return SequenceMatcher(None, text1, text2).ratio()

# -------------------------------
# MAIN PROCESSING
# -------------------------------
INPUT_DIR = "/Users/suyashmaniyar/Desktop/Hackumass/hackumass test images"
OUTPUT_DIR = f"captured_slides_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
os.makedirs(OUTPUT_DIR, exist_ok=True)

image_files = sorted(glob.glob(os.path.join(INPUT_DIR, "*.*")))
last_corners = None
prev_crop_gray = None
prev_text = None

# Initialize EasyOCR reader (English language)
print("Initializing EasyOCR reader...")
reader = easyocr.Reader(['en'], gpu=False)
print("OCR reader initialized!\n")

for idx, file_path in enumerate(image_files):
    frame = cv2.imread(file_path)
    if frame is None:
        continue

    corners = find_screen(frame, last_corners)
    if corners is None:
        continue

    last_corners = corners
    cropped = extract_bbox_with_padding(frame, corners, pad=EXTRA_PAD)

    # Save every cropped slide
    out_path = os.path.join(OUTPUT_DIR, f"slide_{idx:03d}.jpg")
    cv2.imwrite(out_path, cropped)

    # Extract text using OCR
    curr_text = extract_text_ocr(cropped, reader)
    
    print(f"\n{'='*60}")
    print(f"Slide {idx}: {os.path.basename(file_path)}")
    print(f"{'='*60}")
    print(f"OCR Text:\n{curr_text if curr_text else '(No text detected)'}")
    print(f"{'-'*60}")

    # Compare similarity with previous crop
    curr_crop_gray = preprocess_gray(cropped)
    if prev_crop_gray is not None:
        ssim_score = ssim(prev_crop_gray, curr_crop_gray)
        print(f"SSIM Score (vs slide {idx-1}): {ssim_score:.4f}")
        
        # Calculate OCR text similarity
        if prev_text is not None:
            ocr_score = calculate_text_similarity(prev_text, curr_text)
            print(f"OCR Matching Score (vs slide {idx-1}): {ocr_score:.4f}")
    
    prev_crop_gray = curr_crop_gray
    prev_text = curr_text

print(f"\n{'='*60}")
print(f"Finished processing {len(image_files)} images.")
print(f"Cropped slides saved in {OUTPUT_DIR}")
print(f"{'='*60}")
