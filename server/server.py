from fastapi import FastAPI, File, UploadFile, Form, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from fastapi.exception_handlers import request_validation_exception_handler
import uvicorn
import cv2
import numpy as np
import ssl
from pathlib import Path
from google import genai
# import google.generativeai as genai
from google.genai import types
import json
import tempfile
import logging

# Fix SSL certificate verification
ssl._create_default_https_context = ssl._create_unverified_context

app = FastAPI(title="HackUMass API Server")

# Add exception handler for validation errors
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    print(f"\n❌ Validation Error:")
    print(f"   URL: {request.url}")
    print(f"   Method: {request.method}")
    print(f"   Headers: {dict(request.headers)}")
    print(f"   Errors: {exc.errors()}")
    return await request_validation_exception_handler(request, exc)

# Global variable for current session folder
current_session_dir = None  # Current conversation session folder (contains everything)

# Directory to save cropped images (relative to server.py location)
SERVER_DIR = Path(__file__).parent

# Base directory for all session data (one folder per session)
SESSIONS_BASE_DIR = SERVER_DIR.parent / "sessions"
SESSIONS_BASE_DIR.mkdir(exist_ok=True)

print(f"📁 All session data will be saved to: {SESSIONS_BASE_DIR.absolute()}")

# Setup logging
LOG_DIR = SERVER_DIR.parent / "logs"
LOG_DIR.mkdir(exist_ok=True)
LOG_FILE = LOG_DIR / "api_logs.log"

# Configure logging with force=True to overwrite existing handlers
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, mode='a'),  # Append mode
        logging.StreamHandler()  # Also print to console
    ],
    force=True  # Force reconfiguration
)
logger = logging.getLogger(__name__)
print(f"📝 Log file: {LOG_FILE.absolute()}")

# Gemini API key
GEMINI_API_KEY = "AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0"

# Gemini prompt
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
# Gemini API functions
# -------------------------------
def analyze_slide_with_gemini(cropped_image, image_path=None):
    """Analyze cropped slide image using Gemini API"""
    try:
        # If image_path is provided, use it; otherwise save to temp file
        if image_path is None or not Path(image_path).exists():
            # Create temp file if path doesn't exist or wasn't provided
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
            temp_path = temp_file.name
            success = cv2.imwrite(temp_path, cropped_image)
            if not success:
                raise Exception(f"Failed to write image to temp file: {temp_path}")
            image_path = temp_path
            temp_file_created = True
        else:
            temp_file_created = False
        
        # Verify file exists before reading
        if not Path(image_path).exists():
            raise FileNotFoundError(f"Image file does not exist: {image_path}")
        
        # Read image bytes
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
        
        if len(image_bytes) == 0:
            raise Exception(f"Image file is empty: {image_path}")
        
        # Call Gemini API
        client = genai.Client(api_key=GEMINI_API_KEY)
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=[
                types.Part.from_bytes(
                    data=image_bytes,
                    mime_type='image/jpeg',
                ),
                GEMINI_PROMPT
            ]
        )
        
        res_text = response.text
        
        # Clean up JSON if wrapped in code blocks
        if res_text.startswith("```json"):
            res_text = res_text.strip("```json\n")
            res_text = res_text.strip("\n```")
        elif res_text.startswith("```"):
            res_text = res_text.strip("```\n")
            res_text = res_text.strip("\n```")
        
        # Parse JSON
        data_dict = json.loads(res_text)
        
        # Clean up temp file if we created one (only if it's a temp file)
        if temp_file_created and image_path is not None and Path(image_path).exists():
            try:
                Path(image_path).unlink()
            except Exception as e:
                print(f"   ⚠️  Warning: Could not delete temp file {image_path}: {e}")
        
        return data_dict
        
    except Exception as e:
        print(f"   ❌ Error analyzing with Gemini: {e}")
        return {
            "title": [],
            "enumeration": [],
            "equation": [],
            "table": [],
            "image": [],
            "code": [],
            "slide_number": [],
            "summary": [f"Error analyzing slide: {str(e)}"]
        }

def reset_session():
    """Reset the conversation session (call when conversation stops or starts)"""
    global current_session_dir
    current_session_dir = None
    print("   🔄 Session state reset: cleared session folder")


# -------------------------------
# API Endpoints
# -------------------------------
@app.get("/")
async def root():
    return {
        "message": "HackUMass API Server is running",
        "endpoint": "/api/process-image",
        "method": "POST",
        "description": "Accepts one image, detects and crops slide, analyzes with Gemini API"
    }

@app.post("/api/process-image")
async def process_image(image: UploadFile = File(...)):
    """
    Endpoint to receive image from the Flutter app.
    - Detects and crops slide from image
    - Analyzes cropped image with Gemini API
    - Saves files to timestamped session folder
    - Returns Gemini analysis JSON
    """
    global current_session_dir
    
    try:
        import datetime
        
        print(f"\n{'='*60}")
        print(f"📸 Image received at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   Filename: {image.filename}")
        print(f"   Content type: {image.content_type}")
        
        # Create session folder if it doesn't exist (first call)
        if current_session_dir is None:
            reset_session()
            session_timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
            current_session_dir = SESSIONS_BASE_DIR / f"session_{session_timestamp}"
            # Ensure base directory and session directory exist
            SESSIONS_BASE_DIR.mkdir(parents=True, exist_ok=True)
            current_session_dir.mkdir(parents=True, exist_ok=True)
            
            print(f"\n🆕 New conversation session started!")
            print(f"📁 Session folder: {current_session_dir.absolute()}")
            print(f"   📂 Each image capture will create its own timestamped subfolder")
        
        # Read image
        contents = await image.read()
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        print(f"   Image: {image.filename}, Size: {len(contents)} bytes ({len(contents)/1024:.2f} KB)")
        
        if img is None:
            return JSONResponse(
                status_code=400,
                content={"error": "Invalid image file"}
            )
        
        # Get timestamp for this image
        image_timestamp = datetime.datetime.now()
        timestamp_str = image_timestamp.strftime('%Y%m%d_%H%M%S_%f')
        
        # Create a subfolder for this specific image capture within the session
        image_subfolder = current_session_dir / f"image_{timestamp_str}"
        try:
            image_subfolder.mkdir(parents=True, exist_ok=True)
            
            # Create subfolders for this image
            (image_subfolder / "cropped").mkdir(parents=True, exist_ok=True)
            (image_subfolder / "original").mkdir(parents=True, exist_ok=True)
            (image_subfolder / "annotated").mkdir(parents=True, exist_ok=True)
            (image_subfolder / "analysis").mkdir(parents=True, exist_ok=True)
            
            print(f"   📂 Created image subfolder: {image_subfolder.name}/")
        except Exception as e:
            print(f"   ❌ Failed to create image subfolder: {e}")
            raise
        
        # Detect and crop slide
        cropped, detected, corners = detect_and_crop_slide(img)
        print(f"   Slide detected: {detected}")
        
        # Determine which image to use for Gemini analysis
        if detected:
            # Slide detected: use cropped image
            image_for_gemini = cropped
            image_path_for_gemini = None  # Will be set after saving
            print(f"   ✅ Using cropped image for Gemini analysis")
        else:
            # Slide not detected: use original image
            image_for_gemini = img
            image_path_for_gemini = None  # Will be set after saving
            print(f"   ⚠️  Slide not detected, using original image for Gemini analysis")
        
        # Draw bounding box and save annotated image (only if slide detected)
        annotated_path = None
        if detected and corners is not None:
            annotated = draw_bounding_box(img, corners)
            annotated_path = image_subfolder / "annotated" / f"annotated_{timestamp_str}.jpg"
            # Ensure annotated directory exists
            annotated_path.parent.mkdir(parents=True, exist_ok=True)
            success = cv2.imwrite(str(annotated_path), annotated)
            if success:
                print(f"   ✅ Saved annotated image: image_{timestamp_str}/annotated/{annotated_path.name}")
            else:
                print(f"   ❌ Failed to save annotated image")
        
        # Save the image that will be analyzed (cropped if detected, original if not)
        saved_image_path = None
        if detected:
            # Save cropped image
            saved_image_path = image_subfolder / "cropped" / f"cropped_{timestamp_str}.jpg"
            try:
                # Ensure cropped directory exists
                saved_image_path.parent.mkdir(parents=True, exist_ok=True)
                success = cv2.imwrite(str(saved_image_path), cropped)
                if success and saved_image_path.exists():
                    print(f"   ✅ Saved cropped image: {image_subfolder.name}/cropped/{saved_image_path.name}")
                    image_path_for_gemini = str(saved_image_path)
                else:
                    print(f"   ❌ Failed to save cropped image to {saved_image_path}")
                    saved_image_path = None
            except Exception as e:
                print(f"   ❌ Exception saving cropped image: {e}")
                saved_image_path = None
        else:
            # Save original image
            saved_image_path = image_subfolder / "original" / f"original_{timestamp_str}.jpg"
            try:
                # Ensure original directory exists
                saved_image_path.parent.mkdir(parents=True, exist_ok=True)
                success = cv2.imwrite(str(saved_image_path), img)
                if success and saved_image_path.exists():
                    print(f"   ✅ Saved original image: {image_subfolder.name}/original/{saved_image_path.name}")
                    image_path_for_gemini = str(saved_image_path)
                else:
                    print(f"   ❌ Failed to save original image to {saved_image_path}")
                    saved_image_path = None
            except Exception as e:
                print(f"   ❌ Exception saving original image: {e}")
                saved_image_path = None
        
        # Analyze with Gemini API
        print(f"   🤖 Analyzing image with Gemini...")
        gemini_result = analyze_slide_with_gemini(image_for_gemini, image_path_for_gemini)
        
        # Save Gemini analysis JSON (timestamped)
        json_timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
        gemini_json_path = image_subfolder / "analysis" / f"analysis_{json_timestamp}.json"
        try:
            # Ensure the analysis directory exists
            gemini_json_path.parent.mkdir(parents=True, exist_ok=True)
            with open(gemini_json_path, 'w') as f:
                json.dump(gemini_result, f, indent=2)
            if gemini_json_path.exists():
                print(f"   ✅ Saved Gemini analysis JSON: {image_subfolder.name}/analysis/{gemini_json_path.name}")
            else:
                print(f"   ❌ Gemini JSON file was not created at {gemini_json_path}")
        except Exception as e:
            print(f"   ❌ Failed to save Gemini JSON: {e}")
            import traceback
            traceback.print_exc()
        
        # Log to file with all required information
        image_path_str = str(saved_image_path) if saved_image_path and saved_image_path.exists() else "N/A"
        logger.info(f"Image processed - Timestamp: {image_timestamp.isoformat()}, "
                   f"Slide detected: {detected}, "
                   f"Image path: {image_path_str}, "
                   f"Gemini response: {json.dumps(gemini_result, ensure_ascii=False)}")
        
        result = {
            "slide_detected": detected,
            "gemini_analysis": gemini_result
        }
        
        # Print the response that will be sent to the app
        print(f"\n📤 Response being sent to app:")
        print(json.dumps(result, indent=2))
        print(f"{'='*60}\n")
        
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
