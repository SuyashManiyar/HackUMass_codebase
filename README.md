# SightScribe

SightScribe is an AI companion designed to make lectures and presentations accessible — especially for people with visual impairments. Point your phone at the screen and SightScribe uses computer vision (CLIP image embeddings plus OCR text matching) to detect slide changes, interprets the on-screen content with Gemini, and turns it into spoken explanations in real time.

Learners ask questions about the current slide—or about earlier slides they couldn’t see—using ElevenLabs speech-to-text. SightScribe routes the transcribed query with the right context to a lightweight LLM for fast reasoning, then returns the answer through ElevenLabs text-to-speech so the conversation never disrupts the presenter.

Instead of passively listening, users interact with the material as it happens: asking follow-ups, revisiting previous slides, and hearing details that would otherwise be missed. See through sound. Learn without barriers.

## Environment Setup

Install the tooling you need to work locally:

- Flutter SDK 3.9.2 or newer (includes Dart)
- Xcode (macOS) or Android SDK + Android Studio/VS Code
- Python 3.11+ for the FastAPI backend (a `.venv` is recommended)
- Node.js 18+ if you plan to run the optional signaling server for remote camera sharing

Clone the repository and install Flutter dependencies:

```bash
git clone https://github.com/SuyashManiyar/HackUMass_codebase.git
cd HackUMass_codebase
flutter pub get
```

Create `.env` beside `lib/main.dart` and provide the runtime keys:

```
FASTAPI_BASE_URL=http://127.0.0.1:8000
SIGNALING_SERVER_URL=http://127.0.0.1:3000
OPENROUTER_API_KEY=sk-...
ELEVENLABS_API_KEY=...
GEMINI_API_KEY=...
SLIDE_CAPTURE_INTERVAL=10
```

The `.env` powers both camera capture (FastAPI), question answering (OpenRouter), and audio interfaces (ElevenLabs). The backend also honors `GEMINI_API_KEY` for slide summarization.

## Before You Run

1. **Bootstrap the Python backend**
   ```bash
   cd HackUMass_codebase
   python -m venv .venv
   source .venv/bin/activate
   pip install -r server/requirements.txt
   export GEMINI_API_KEY=...
   uvicorn server.main:app --host 0.0.0.0 --port 8000
   ```
2. **(Optional) Start the signaling server** for remote camera sharing:
   ```bash
   cd signaling-server
   npm install
   npm start
   ```
3. **Launch Flutter** on your device or simulator:
   ```bash
   flutter run
   ```

Once the backend is up and the Flutter app is running, tap **Start Capturing** in the app to begin a session.

## GuideLens Pipeline

#### ✅ Full System Pipeline (Condensed w/ Arrows)

```
START SESSION
     ↓
Camera video feed → Flutter client
     ↓ (periodic frames)
Send frame → FastAPI /process_slide
     ↓
[FastAPI]
  • CLIP similarity vs last slide
  • OCR → text similarity
     ↓
New slide decision rule:
  IF (CLIP < 0.88) OR (TextSim < 0.65) → NEW SLIDE
  ELSE → SAME SLIDE → return latest summary
     ↓
IF NEW SLIDE:
     ↓
Gemini 2.5 Flash → structured JSON:
  {
    title[], enumeration[], equations[],
    display_summary[], end_summary[], ... etc.
  }
     ↓
Store summary → update:
  • latest slide
  • slide history[]
     ↓
Return JSON → Flutter
     ↓
UI shows → “Slide Summary”
```

#### ✅ Voice Pipeline

```
User taps mic → record speech
     ↓
Speech-to-Text (ElevenLabs / STT)
     ↓
Text query + latest slide summary
+ slide history (context)
     ↓
Send → OpenRouter (GPT-4o-mini)
     ↓
LLM generates short 25-word reply
     ↓
Text-To-Speech → ElevenLabs TTS
     ↓
User hears answer
     ↓
Follow-up questions allowed (loop)
```

#### ✅ Session Finalization

```
At Stop Capturing:
     ↓
We have:
  • slide_history[]
  • per-slide end_summary[]
     ↓
Generate overall lecture summary (Gemini)
     ↓
Store:
  • all slide JSONs
  • overall_summary
     ↓
Show “End Summary” screen
```

#### 🔹 Components

**Client (Flutter)** – captures frames, renders summaries, manages slide history, and handles the voice assistant UX.  
**Backend (FastAPI)** – performs frame differencing (CLIP + OCR), calls Gemini, maintains session state, and returns structured JSON.  
**Models** – CLIP for similarity, OCR for text extraction, Gemini for slide summaries, OpenRouter for QA, and ElevenLabs for both STT and TTS.

#### ✅ Key Logic Rules

- Slide is replaced only if:

  ```
  clip_sim < 0.88   OR
  text_sim < 0.65
  ```

- Only a **new** slide triggers Gemini extraction and history append.

## Project Structure

```
lib/
├── core/                       # App state + env helpers
├── features/
│   ├── camera/                 # Camera controller & capture service
│   ├── slide_pipeline/         # Slide client, repository, scheduler
│   ├── voice_pipeline/         # Conversation controller + STT/TTS
│   ├── llm/                    # OpenRouter bridge
│   └── screens/                # Supporting UI flows
├── services/                   # FastAPI client, signaling, etc.
├── utils/                      # Logger, debouncer, helpers
└── main.dart                   # App entry, primary UI

server/
├── main.py                     # FastAPI entry point
├── routers/                    # /process_slide, /health
└── core/                       # CLIP, OCR, Gemini orchestration

signaling-server/
└── index.js                    # Optional WebRTC signaling server
```

## Troubleshooting

- Run `flutter clean && flutter pub get` if builds fail.
- Ensure `.env` is present and populated before launching the app.
- If the backend rejects requests, confirm `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, and `ELEVENLABS_API_KEY` are exported.
- To reset the voice assistant, stop capturing and start again; this reinitializes the conversation controller.

## Contributing

Pull requests are welcome—keep code formatted with `flutter format .` and ensure both backend and Flutter app run locally (`uvicorn` and `flutter run`) before submitting.

## Project Structure

```
lib/
├── core/
│   ├── app_state.dart              # Slide summary state
│   └── env.dart                    # Environment helpers (.env access)
├── features/
│   ├── camera/
│   │   ├── camera_capture_service.dart
│   │   └── camera_controller.dart
│   ├── slide_pipeline/
│   │   ├── slide_client.dart       # POST /process_slide
│   │   ├── slide_repo.dart         # Stores latest OCR + summary
│   │   └── slide_scheduler.dart    # Periodic capture loop
│   ├── voice_pipeline/
│   │   ├── conversation_controller.dart
│   │   ├── voice_pipeline.dart
│   │   ├── stt/
│   │   └── tts/
│   ├── llm/
│   │   └── llm_service.dart
│   └── screens/
│       ├── connect_camera_screen.dart
│       ├── remote_camera_view_screen.dart
│       ├── share_camera_screen.dart
│       └── test_pipeline_page.dart
├── services/
│   ├── camera_stream_service.dart
│   ├── fastapi_client.dart        # Shared FastAPI HTTP client
│   ├── remote_camera_manager.dart
│   └── signaling_service.dart
├── utils/
│   ├── connection_monitor.dart
│   ├── debouncer.dart
│   ├── error_handler.dart
│   └── logger.dart
└── main.dart                      # App entry point & home UI

server/
├── main.py                        # FastAPI application
├── routers/                       # /process_slide & /health
└── core/                          # OCR, Gemini, change detection

signaling-server/
├── index.js
├── package.json
└── README.md
```

## Troubleshooting

### Flutter Issues

**"flutter: command not found"**
- Install Flutter SDK and add to PATH
- Verify with: `flutter doctor`

**Build errors**
```bash
flutter clean
flutter pub get
flutter run
```

**Permission errors**
- Check AndroidManifest.xml has camera/microphone permissions
- Check Info.plist has usage descriptions (iOS)

### Signaling Server Issues

**Cannot connect to server**
- Ensure server is running: `npm start` in signaling-server directory
- Check firewall allows connections on port 3000
- Verify server URL in app matches your server's IP

**"Port already in use"**
```bash
PORT=3001 npm start
```
Then update the app's server URL accordingly

### Connection Issues

**"Invalid or expired pairing code"**
- Codes expire after 1 hour
- Codes are single-use
- Ensure sender started sharing before receiver connects

**"Connection timeout"**
- Check both devices are on the same network or have internet access
- Verify signaling server is accessible from both devices
- Check firewall settings

**Poor video quality**
- Check network connection strength
- Move closer to WiFi router
- Close other bandwidth-intensive apps

## Network Requirements

- **Local Network Testing**: Both devices on same WiFi
- **Internet Testing**: Both devices need internet access
- **Bandwidth**: ~1-2 Mbps for 720p video
- **Latency**: Best with < 100ms ping

## Security Notes

- Video data is encrypted using WebRTC's built-in DTLS-SRTP
- Pairing codes expire after 1 hour
- Signaling server doesn't store or route video data
- All video streams are peer-to-peer

## Known Limitations

- Frame capture from remote stream requires platform-specific implementation
- Connection quality monitoring is basic (can be enhanced)
- No support for multiple simultaneous connections
- Pairing codes are case-insensitive but displayed in uppercase

## Future Enhancements

- [ ] Implement frame capture from remote stream
- [ ] Add support for multiple receivers
- [ ] Enhanced connection quality monitoring
- [ ] Recording capability
- [ ] Chat/messaging during video call
- [ ] Screen sharing option

## Dependencies

### Flutter Packages
- `flutter_webrtc`: ^0.9.48 - WebRTC implementation
- `socket_io_client`: ^2.0.3+1 - WebSocket client
- `camera`: ^0.10.5+9 - Camera access
- `permission_handler`: ^11.3.0 - Runtime permissions
- `image_picker`: ^1.0.7 - Image selection
- `google_generative_ai`: ^0.4.0 - Gemini AI
- `path_provider`: ^2.1.2 - File system paths

### Node.js Packages
- `express`: ^4.18.2 - Web server
- `socket.io`: ^4.6.1 - WebSocket server
- `cors`: ^2.8.5 - CORS middleware

## License

MIT

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review signaling server logs
3. Check Flutter console output
4. Ensure all prerequisites are installed

## Contributing

Contributions are welcome! Please ensure:
- Code follows Flutter best practices
- All features are tested on both Android and iOS
- Documentation is updated
