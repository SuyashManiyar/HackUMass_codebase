import cv2
import sys
sys.path.append('..')

# Import the compare function directly from app.py
from computer_vision.app import compare_images

def compare_slides_directly(image1_path, image2_path):
    """
    Compare two slide images by directly using the comparison function
    (No need to run the FastAPI server)
    
    Args:
        image1_path: Path to first image
        image2_path: Path to second image
    
    Returns:
        dict: Comparison results with ssim_score, ocr_similarity, texts, etc.
    """
    # Read images using OpenCV
    img1 = cv2.imread(image1_path)
    img2 = cv2.imread(image2_path)
    
    if img1 is None or img2 is None:
        return {"error": "Could not read one or both images"}
    
    # Use the compare_images function directly
    result = compare_images(img1, img2)
    
    return result


# Example usage
if __name__ == "__main__":
    # Compare two images without running the API server
    result = compare_slides_directly(
        "hackumass test images/2.jpeg",
        "hackumass test images/3.jpeg"
    )
    
    print("Comparison Results:")
    print(f"SSIM Score: {result.get('ssim_score')}")
    print(f"OCR Similarity: {result.get('ocr_similarity')}")
    print(f"Same Slide: {result.get('are_same_slide')}")
    print(f"\nImage 1 Text: {result.get('image1_text')[:100]}...")
    print(f"\nImage 2 Text: {result.get('image2_text')[:100]}...")
