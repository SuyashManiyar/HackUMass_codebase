from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
import easyocr
from difflib import SequenceMatcher
import ssl

# Fix SSL certificate verification
ssl._create_default_https_context = ssl._create_unverified_context

# Initialize EasyOCR reader
print("Initializing EasyOCR...")
reader = easyocr.Reader(['en'], gpu=False)
print("EasyOCR ready!")

app = FastAPI(title="Slide Comparison API", version="1.0")

# Constants
WARPED_WIDTH = 1000
WARPED_HEIGHT = 600
EXTRA_PAD = 30


# -------------------------------
# Slide detection functions
# -------------------------------
def order_points(pts):
    """Sort 4-point contour in top-left, top-right, bottom-right, bottom-left order"""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect


def get_centroid(contour):
    """Calculate the center (centroid) of a contour"""
    if contour.shape == (4, 2):
        M = cv2.moments(contour.reshape(4, 1, 2))
    else:
        M = cv2.moments(contour)
    if M["m00"] == 0:
        return None, None
    return int(M["m10"] / M["m00"]), int(M["m01"] / M["m00"])


def find_screen(frame, last_corners=None):
    """Find the largest 4-sided contour (slide/screen) in the frame"""
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
    """Extract bounding box with padding around detected corners"""
    x, y, w, h = cv2.boundingRect(corners.astype(int))
    x1 = max(x - pad, 0)
    y1 = max(y - pad, 0)
    x2 = min(x + w + pad, frame.shape[1])
    y2 = min(y + h + pad, frame.shape[0])
    return frame[y1:y2, x1:x2]


def detect_and_crop_slide(frame):
    """Detect slide in frame and return cropped image"""
    corners = find_screen(frame)
    if corners is None:
        # If no slide detected, return original frame
        return frame, False
    
    cropped = extract_bbox_with_padding(frame, corners, pad=EXTRA_PAD)
    return cropped, True


# -------------------------------
# Comparison functions
# -------------------------------
def preprocess_gray(img):
    """Convert image to gray and resize"""
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.resize(g, (WARPED_WIDTH, WARPED_HEIGHT))
    return g


def extract_text_ocr(img):
    """Extract text from image using EasyOCR"""
    results = reader.readtext(img)
    text = ' '.join([r[1] for r in results])
    return text.strip()


def calculate_text_similarity(text1, text2):
    """Calculate character-level similarity between two texts"""
    if not text1 and not text2:
        return 1.0
    if not text1 or not text2:
        return 0.0
    return SequenceMatcher(None, text1, text2).ratio()


def compare_images(img1, img2):
    """Compare two images and return SSIM score, OCR texts, and similarity"""
    # Preprocess for SSIM
    gray1 = preprocess_gray(img1)
    gray2 = preprocess_gray(img2)
    
    # Calculate SSIM (image similarity)
    ssim_score = ssim(gray1, gray2)
    
    # Extract text using OCR
    text1 = extract_text_ocr(img1)
    text2 = extract_text_ocr(img2)
    
    # Calculate text similarity
    text_similarity = calculate_text_similarity(text1, text2)
    
    return {
        "ssim_score": float(round(ssim_score, 4)),
        "ocr_similarity": float(round(text_similarity, 4)),
        "image1_text": text1,
        "image2_text": text2,
        "are_same_slide": bool(ssim_score > 0.95 and text_similarity > 0.95)
    }


# -------------------------------
# API Endpoints
# -------------------------------
@app.post("/compare/")
async def compare_two_images(image1: UploadFile = File(...), image2: UploadFile = File(...)):
    """
    Upload two images, detect and crop slides, then compare them.
    Returns SSIM score, OCR similarity, extracted text, and whether they're the same slide.
    """
    try:
        # Read image1
        contents1 = await image1.read()
        nparr1 = np.frombuffer(contents1, np.uint8)
        img1 = cv2.imdecode(nparr1, cv2.IMREAD_COLOR)
        
        # Read image2
        contents2 = await image2.read()
        nparr2 = np.frombuffer(contents2, np.uint8)
        img2 = cv2.imdecode(nparr2, cv2.IMREAD_COLOR)
        
        if img1 is None or img2 is None:
            return JSONResponse(
                status_code=400,
                content={"error": "Invalid image file(s)"}
            )
        
        # Detect and crop slides from both images
        cropped1, detected1 = detect_and_crop_slide(img1)
        cropped2, detected2 = detect_and_crop_slide(img2)
        
        # Compare the cropped images
        result = compare_images(cropped1, cropped2)
        
        # Add detection info to result
        result["slide1_detected"] = detected1
        result["slide2_detected"] = detected2
        
        return result
        
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )


@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "Slide Comparison API with Auto-Detection",
        "endpoint": "/compare/",
        "method": "POST",
        "parameters": "image1 and image2 (files)",
        "description": "Automatically detects and crops slides from images before comparison",
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
