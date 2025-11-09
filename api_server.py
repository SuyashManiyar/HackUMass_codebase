from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
import uvicorn

app = FastAPI(title="HackUMass API Server")

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"message": "HackUMass API Server is running"}

@app.post("/api/process-image")
async def process_image(image: UploadFile = File(...)):
    """
    Endpoint to receive images from the Flutter app.
    Currently returns an empty JSON response.
    """
    try:
        print(f"\n{'='*60}")
        print(f"📸 Image received at {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   Filename: {image.filename}")
        print(f"   Content-Type: {image.content_type}")
        
        # Read the image file (optional - for future processing)
        image_bytes = await image.read()
        print(f"   Image size: {len(image_bytes)} bytes ({len(image_bytes)/1024:.2f} KB)")
        
        # You can process the image here later
        
        print(f"{'='*60}\n")
        
        # Return empty JSON response
        return {}
    except Exception as e:
        print(f"❌ Error processing image: {e}")
        return {"error": str(e)}

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

