## Slide Processing Server

This FastAPI backend detects slide changes using OCR and produces Gemini-powered summaries for the Flutter client.

### API

- `GET /health` — simple readiness probe.
- `POST /process_slide` — accepts a JPEG image and returns `{ "changed": bool, "summary": {...}, "slide_detected": bool }`.

### Pipeline

1. Detect slide rectangle with OpenCV and crop the slide region.
2. Extract text from the crop using EasyOCR.
3. Compare OCR text against the cached slide text (sequence ratio + token delta).
4. If the slide changed, call Gemini Vision for a structured JSON summary and persist the OCR, summary, and crop under `storage/`.

### Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY="your-key"    # optional; defaults to the bundled dev key
uvicorn server.main:app --host 0.0.0.0 --port 8000
```

### Dependencies

`requirements.txt` includes OpenCV, EasyOCR, and the Gemini SDK. EasyOCR pulls in PyTorch, so the first installation can take a few minutes.


