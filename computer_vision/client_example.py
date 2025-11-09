import requests

# Make sure the FastAPI server is running first!
# Run: python3 -m uvicorn computer_vision.app:app --host 0.0.0.0 --port 8000

API_URL = "http://localhost:8000/compare/"

def compare_slides(image1_path, image2_path):
    """
    Compare two slide images using the FastAPI endpoint
    
    Args:
        image1_path: Path to first image
        image2_path: Path to second image
    
    Returns:
        dict: Comparison results with ssim_score, ocr_similarity, texts, etc.
    """
    # Open both images
    with open(image1_path, 'rb') as img1, open(image2_path, 'rb') as img2:
        files = {
            'image1': ('image1.jpg', img1, 'image/jpeg'),
            'image2': ('image2.jpg', img2, 'image/jpeg')
        }
        
        # Make POST request
        response = requests.post(API_URL, files=files)
        
        if response.status_code == 200:
            return response.json()
        else:
            return {"error": f"Request failed with status {response.status_code}"}


# Example usage
if __name__ == "__main__":
    # Compare two images
    result = compare_slides(
        "hackumass test images/2.jpeg",
        "hackumass test images/3.jpeg"
    )
    
    print("Comparison Results:")
    print(f"SSIM Score: {result.get('ssim_score')}")
    print(f"OCR Similarity: {result.get('ocr_similarity')}")
    print(f"Same Slide: {result.get('are_same_slide')}")
    print(f"\nImage 1 Text: {result.get('image1_text')[:100]}...")
    print(f"\nImage 2 Text: {result.get('image2_text')[:100]}...")
