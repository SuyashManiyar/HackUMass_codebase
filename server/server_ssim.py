from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from typing import Optional
import uvicorn
import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
import ssl
from pathlib import Path

# Fix SSL certificate verification
ssl._create_default_https_context = ssl._create_unverified_context

app = FastAPI(title="HackUMass API Server")

# Global variable to store previous cropped image
previous_cropped_image = None
previous_cropped_detected = False
current_session_dir = None  # Current conversation session folder
current_annotated_dir = None  # Current annotated images folder

# Directory to save cropped images (relative to server.py location)
SERVER_DIR = Path(__file__).parent
CROPPED_IMAGES_DIR = SERVER_DIR.parent / "cropped_images"
CROPPED_IMAGES_DIR.mkdir(exist_ok=True)

# Base directory for conversation sessions
SESSIONS_DIR = SERVER_DIR.parent / "conversation_sessions"
SESSIONS_DIR.mkdir(exist_ok=True)

# Base directory for annotated images (with bounding boxes)
ANNOTATED_DIR = SERVER_DIR.parent / "annotated_images"
ANNOTATED_DIR.mkdir(exist_ok=True)

print(f"📁 Cropped images will be saved to: {CROPPED_IMAGES_DIR.absolute()}")
print(f"📁 Conversation sessions will be saved to: {SESSIONS_DIR.absolute()}")
print(f"📁 Annotated images will be saved to: {ANNOTATED_DIR.absolute()}")

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    """Detect slide in frame and return cropped image and corners"""
    corners = find_screen(frame)
    if corners is None:
        # If no slide detected, return original frame
        return frame, False, None

    cropped = extract_bbox_with_padding(frame, corners, pad=EXTRA_PAD)
    return cropped, True, corners

def draw_bounding_box(frame, corners):
    """Draw bounding box on the frame and return annotated image"""
    if corners is None:
        return frame.copy()
    
    annotated = frame.copy()
    # Convert corners to integer points
    pts = corners.astype(int)
    
    # Draw the bounding box (4-sided polygon)
    cv2.polylines(annotated, [pts], isClosed=True, color=(0, 255, 0), thickness=3)
    
    # Draw corner points
    for i, pt in enumerate(pts):
        cv2.circle(annotated, tuple(pt), 8, (0, 0, 255), -1)
        cv2.putText(annotated, str(i+1), (pt[0] + 10, pt[1]), 
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
    
    return annotated


# -------------------------------
# Comparison functions
# -------------------------------
def preprocess_gray(img):
    """Convert image to gray and resize"""
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.resize(g, (WARPED_WIDTH, WARPED_HEIGHT))
    return g

def compare_images(img1, img2):
    """Compare two images and return SSIM score"""
    # Preprocess for SSIM
    gray1 = preprocess_gray(img1)
    gray2 = preprocess_gray(img2)

    # Calculate SSIM (image similarity)
    ssim_score = ssim(gray1, gray2)

    return {
        "ssim_score": float(round(ssim_score, 4)),
        "are_same_slide": bool(ssim_score > 0.60)
    }

def reset_session():
    """Reset the conversation session (call when conversation stops or starts)"""
    global previous_cropped_image, previous_cropped_detected, current_session_dir, current_annotated_dir
    previous_cropped_image = None
    previous_cropped_detected = False
    current_session_dir = None
    current_annotated_dir = None
    print("   🔄 Session state reset: cleared previous images and folders")


# -------------------------------
# API Endpoints
# -------------------------------
@app.get("/")
async def root():
    return {
        "message": "HackUMass API Server is running",
        "endpoint": "/api/process-image",
        "method": "POST",
        "description": "Accepts two images, detects and crops slides, then compares them"
    }

@app.post("/api/process-image")
async def process_image(image1: UploadFile = File(...), image2: UploadFile = File(None)):
    """
    Endpoint to receive images from the Flutter app.
    Accepts 1 or 2 images for comparison.
    - If 2 images provided: compares cropped images, saves image2 as previous for next call
    - If 1 image provided: uses previous image2 (from last call) as image1, compares with current
    Always uses only cropped images for comparison.
    """
    global previous_cropped_image, previous_cropped_detected, current_session_dir, current_annotated_dir
    
    try:
        import datetime
        
        print(f"\n{'='*60}")
        print(f"📸 Image(s) received at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # Handle case when only one image is provided
        if image2 is None:
            if previous_cropped_image is None:
                # No previous image - this is the start of a new conversation
                # Reset everything first
                reset_session()
                
                # Create a new session folder and annotated folder
                global current_session_dir, current_annotated_dir
                session_timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                current_session_dir = SESSIONS_DIR / f"session_{session_timestamp}"
                current_session_dir.mkdir(exist_ok=True)
                current_annotated_dir = ANNOTATED_DIR / f"annotated_{session_timestamp}"
                current_annotated_dir.mkdir(exist_ok=True)
                print(f"\n🆕 New conversation session started!")
                print(f"🔄 All previous state has been reset")
                print(f"📁 Session folder: {current_session_dir.absolute()}")
                print(f"📁 Annotated folder: {current_annotated_dir.absolute()}")
                
                # No previous image - compare image with itself (first call)
                contents1 = await image1.read()
                nparr1 = np.frombuffer(contents1, np.uint8)
                img1 = cv2.imdecode(nparr1, cv2.IMREAD_COLOR)
                
                if img1 is None:
                    return JSONResponse(
                        status_code=400,
                        content={"error": "Invalid image1 file"}
                    )
                
                # Detect and crop slide from image1
                cropped1, detected1, corners1 = detect_and_crop_slide(img1)
                print(f"   Image1: {image1.filename}, Slide detected: {detected1}")
                
                # Draw bounding box and save annotated image
                if detected1 and corners1 is not None:
                    annotated1 = draw_bounding_box(img1, corners1)
                    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
                    annotated_path = current_annotated_dir / f"annotated1_{timestamp}.jpg"
                    cv2.imwrite(str(annotated_path), annotated1)
                    print(f"   Saved annotated image1: {annotated_path.name}")
                
                # Compare image with itself (first call - no previous image)
                result = compare_images(cropped1, cropped1)
                result["slide1_detected"] = detected1
                result["slide2_detected"] = detected1
                result["is_first_call"] = True
                
                print(f"   SSIM Score: {result['ssim_score']} (compared with itself - first call)")
                print(f"   Same Slide: {result['are_same_slide']}")
                print(f"   (Comparison used only cropped images)")
                
                # Save initial image to session folder
                timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
                initial_path = current_session_dir / f"initial_{timestamp}.jpg"
                cv2.imwrite(str(initial_path), cropped1)
                print(f"   Saved initial image to session: {initial_path}")
                print(f"{'='*60}\n")
                
                # Store as previous for next call
                previous_cropped_image = cropped1.copy()
                previous_cropped_detected = detected1
                
                return result
            else:
                # Use previous image2 as image1, current image1 as image2
                cropped1 = previous_cropped_image.copy()
                detected1 = previous_cropped_detected
                print(f"   Using previous image2 as image1 (detected: {detected1})")
                
                # Read current image as image2
                contents2 = await image1.read()  # image1 is actually the new image
                nparr2 = np.frombuffer(contents2, np.uint8)
                img2 = cv2.imdecode(nparr2, cv2.IMREAD_COLOR)
                
                print(f"   Image2 (current): {image1.filename}, Size: {len(contents2)} bytes ({len(contents2)/1024:.2f} KB)")
                
                if img2 is None:
                    return JSONResponse(
                        status_code=400,
                        content={"error": "Invalid image2 file"}
                    )
                
                # Detect and crop slide from image2
                cropped2, detected2, corners2 = detect_and_crop_slide(img2)
                print(f"   Slide2 detected: {detected2}")
                
                # Draw bounding box and save annotated image
                if detected2 and corners2 is not None:
                    annotated2 = draw_bounding_box(img2, corners2)
                    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
                    annotated_path = current_annotated_dir / f"annotated2_{timestamp}.jpg"
                    cv2.imwrite(str(annotated_path), annotated2)
                    print(f"   Saved annotated image2: {annotated_path.name}")
                
                # Compare ONLY the cropped images
                result = compare_images(cropped1, cropped2)
                
                # Add detection info to result
                result["slide1_detected"] = detected1
                result["slide2_detected"] = detected2
                
                print(f"   SSIM Score: {result['ssim_score']}")
                print(f"   Same Slide: {result['are_same_slide']}")
                
                # Save cropped images to session folder
                timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
                if current_session_dir is not None:
                    # Save both previous and current images to session folder
                    prev_path = current_session_dir / f"prev_{timestamp}.jpg"
                    curr_path = current_session_dir / f"curr_{timestamp}.jpg"
                    cv2.imwrite(str(prev_path), cropped1)
                    cv2.imwrite(str(curr_path), cropped2)
                    
                    if not result['are_same_slide']:
                        print(f"   ⚠️  Different slide detected! Saved to session folder:")
                        print(f"      Previous: {prev_path.name}")
                        print(f"      Current:  {curr_path.name}")
                    else:
                        print(f"   ✓ Same slide - saved to session folder:")
                        print(f"      Previous: {prev_path.name}")
                        print(f"      Current:  {curr_path.name}")
                else:
                    print(f"   ⚠️  Warning: No session folder found, images not saved")
                
                print(f"   (Comparison used only cropped images)")
                print(f"{'='*60}\n")
                
                # Store image2 as previous for next call
                previous_cropped_image = cropped2.copy()
                previous_cropped_detected = detected2
                
                return result
        
        # Two images provided - normal flow
        # Read image1 from request
        contents1 = await image1.read()
        nparr1 = np.frombuffer(contents1, np.uint8)
        img1 = cv2.imdecode(nparr1, cv2.IMREAD_COLOR)
        
        print(f"   Image1: {image1.filename}, Size: {len(contents1)} bytes ({len(contents1)/1024:.2f} KB)")
        
        if img1 is None:
            return JSONResponse(
                status_code=400,
                content={"error": "Invalid image1 file"}
            )
        
        # Detect and crop slide from image1
        cropped1, detected1, corners1 = detect_and_crop_slide(img1)
        print(f"   Slide1 detected: {detected1}")
        
        # Draw bounding box and save annotated image
        if detected1 and corners1 is not None:
            annotated1 = draw_bounding_box(img1, corners1)
            timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
            annotated_path = current_annotated_dir / f"annotated1_{timestamp}.jpg"
            cv2.imwrite(str(annotated_path), annotated1)
            print(f"   Saved annotated image1: {annotated_path.name}")
        
        # Read image2
        contents2 = await image2.read()
        nparr2 = np.frombuffer(contents2, np.uint8)
        img2 = cv2.imdecode(nparr2, cv2.IMREAD_COLOR)
        
        print(f"   Image2: {image2.filename}, Size: {len(contents2)} bytes ({len(contents2)/1024:.2f} KB)")
        
        if img2 is None:
            return JSONResponse(
                status_code=400,
                content={"error": "Invalid image2 file"}
            )
        
        # Detect and crop slide from image2
        cropped2, detected2, corners2 = detect_and_crop_slide(img2)
        print(f"   Slide2 detected: {detected2}")
        
        # Draw bounding box and save annotated image
        if detected2 and corners2 is not None:
            annotated2 = draw_bounding_box(img2, corners2)
            timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
            annotated_path = current_annotated_dir / f"annotated2_{timestamp}.jpg"
            cv2.imwrite(str(annotated_path), annotated2)
            print(f"   Saved annotated image2: {annotated_path.name}")
        
        # Compare ONLY the cropped images
        result = compare_images(cropped1, cropped2)
        
        # Add detection info to result
        result["slide1_detected"] = detected1
        result["slide2_detected"] = detected2
        
        print(f"   SSIM Score: {result['ssim_score']}")
        print(f"   Same Slide: {result['are_same_slide']}")
        
        # Save cropped images to session folder
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        if current_session_dir is not None:
            # Save both previous and current images to session folder
            prev_path = current_session_dir / f"prev_{timestamp}.jpg"
            curr_path = current_session_dir / f"curr_{timestamp}.jpg"
            cv2.imwrite(str(prev_path), cropped1)
            cv2.imwrite(str(curr_path), cropped2)
            
            if not result['are_same_slide']:
                print(f"   ⚠️  Different slide detected! Saved to session folder:")
                print(f"      Previous: {prev_path.name}")
                print(f"      Current:  {curr_path.name}")
            else:
                print(f"   ✓ Same slide - saved to session folder:")
                print(f"      Previous: {prev_path.name}")
                print(f"      Current:  {curr_path.name}")
        else:
            print(f"   ⚠️  Warning: No session folder found, images not saved")
        
        print(f"   (Comparison used only cropped images)")
        print(f"{'='*60}\n")
        
        # Store image2 as previous for next call
        previous_cropped_image = cropped2.copy()
        previous_cropped_detected = detected2
        
        return result
        
    except Exception as e:
        print(f"❌ Error processing image: {e}")
        import traceback
        traceback.print_exc()
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

if __name__ == "__main__":
    import socket
    
    # Get local IP address
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Connect to a remote address (doesn't actually send data)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
    except Exception:
        local_ip = '127.0.0.1'
    finally:
        s.close()
    
    print("\n" + "="*60)
    print("🚀 HackUMass API Server Starting...")
    print("="*60)
    print(f"📍 Server running on:")
    print(f"   Local:   http://127.0.0.1:8000")
    print(f"   Network: http://{local_ip}:8000")
    print(f"\n📡 API Endpoint: http://{local_ip}:8000/api/process-image")
    print(f"\n💡 Update your Flutter app with this IP: {local_ip}")
    print("="*60 + "\n")
    
    # Run on all network interfaces (0.0.0.0) so it's accessible from other devices
    # Port 8000 is the default
    uvicorn.run(app, host="0.0.0.0", port=8000)
