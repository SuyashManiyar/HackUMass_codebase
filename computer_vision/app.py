from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
import cv2
import numpy as np
from skimage.metrics import structural_similarity as ssim
import easyocr
from difflib import SequenceMatcher
import tempfile
import ssl
import os

# Fix SSL certificate verification
ssl._create_default_https_context = ssl._create_unverified_context

# Initialize EasyOCR reader
print("Initializing EasyOCR...")
reader = easyocr.Reader(['en'], gpu=False)
print("EasyOCR ready!")

app = FastAPI(title="Slide Comparison API", version="1.0")


def compare_images(img1, img2):
    """Compare two images and return SSIM score, OCR texts, and similarity"""
    # Resize images to same size for comparison
    WARPED_WIDTH, WARPED_HEIGHT = 1000, 600
    
    # Convert to grayscale and resize
    gray1 = cv2.cvtColor(img1, cv2.COLOR_BGR2GRAY)
    gray1 = cv2.resize(gray1, (WARPED_WIDTH, WARPED_HEIGHT))
    
    gray2 = cv2.cvtColor(img2, cv2.COLOR_BGR2GRAY)
    gray2 = cv2.resize(gray2, (WARPED_WIDTH, WARPED_HEIGHT))
    
    # Calculate SSIM (image similarity)
    ssim_score = ssim(gray1, gray2)
    
    # Extract text using OCR
    results1 = reader.readtext(img1)
    text1 = ' '.join([r[1] for r in results1])
    
    results2 = reader.readtext(img2)
    text2 = ' '.join([r[1] for r in results2])
    
    # Calculate text similarity
    if not text1 and not text2:
        text_similarity = 1.0
    elif not text1 or not text2:
        text_similarity = 0.0
    else:
        text_similarity = SequenceMatcher(None, text1, text2).ratio()
    
    return {
        "ssim_score": float(round(ssim_score, 4)),
        "ocr_similarity": float(round(text_similarity, 4)),
        "image1_text": text1.strip(),
        "image2_text": text2.strip(),
        "are_same_slide": bool(ssim_score > 0.95 and text_similarity > 0.95)
    }


@app.post("/compare/")
async def compare_two_images(image1: UploadFile = File(...), image2: UploadFile = File(...)):
    """
    Upload two images and get comparison results.
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
        
        # Compare images
        result = compare_images(img1, img2)
        
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
        "message": "Slide Comparison API",
        "endpoint": "/compare/",
        "method": "POST",
        "parameters": "image1 and image2 (files)",
        "docs": "/docs"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
