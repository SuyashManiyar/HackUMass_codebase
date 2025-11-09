# HackUMass Camera App

A Flutter mobile application that enables camera capture with AI-powered image description using Google's Gemini AI, plus real-time camera feed sharing between devices using WebRTC.

## Features

### 1. Local Camera Capture
- Capture photos using device camera
- AI-powered image description using Gemini AI
- Simple and intuitive interface

### 2. Remote Camera Feed Sharing (NEW)
- Share your camera feed with another device in real-time
- Connect to a remote camera using a pairing code
- Peer-to-peer video streaming with WebRTC
- Low latency and secure connections
- Switch between front and back cameras while streaming

## Prerequisites

### Development Environment
- Flutter SDK (3.9.2 or higher)
- Dart SDK (included with Flutter)
- Android Studio or VS Code with Flutter extensions
- Android SDK (for Android development)
- Xcode (for iOS development, macOS only)

### For Remote Camera Feature
- Node.js (v14 or higher) for signaling server
- npm or yarn package manager

## Installation

### 1. Clone the Repository
```bash
git clone <repository-url>
cd HackUMass_codebase
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Set Up Signaling Server
```bash
cd signaling-server
npm install
```

## Configuration

### Signaling Server URL
Update the server URL in `lib/main.dart`:
```dart
static const String _serverUrl = 'http://YOUR_SERVER_IP:3000';
```

For local testing:
- Use `http://localhost:3000` when testing on emulator
- Use `http://YOUR_LOCAL_IP:3000` when testing on physical devices
- Use `http://10.0.2.2:3000` for Android emulator to access host machine

### Gemini API Key
The app includes a demo API key. For production, replace it in `lib/main.dart`:
```dart
static const String _apiKey = 'YOUR_GEMINI_API_KEY';
```

Get your API key from: https://makersuite.google.com/app/apikey

## Running the Application

### 1. Start the Signaling Server
```bash
cd signaling-server
npm start
```

The server will run on `http://localhost:3000`

### 2. Run the Flutter App

**On Android Emulator:**
```bash
flutter run
```

**On Physical Device:**
1. Enable USB debugging on your device
2. Connect via USB
3. Run:
```bash
flutter run
```

**On iOS Simulator (macOS only):**
```bash
flutter run -d ios
```

## Usage

### Local Camera Capture
1. Tap "Open Local Camera"
2. Take a photo
3. Tap "Describe Image" to get AI description

### Remote Camera Sharing

#### As Sender (Share Your Camera):
1. Tap "Share Camera"
2. Grant camera and microphone permissions
3. Share the displayed pairing code with the receiver
4. Wait for receiver to connect
5. Use "Switch Camera" to toggle between front/back
6. Tap "Stop Sharing" when done

#### As Receiver (Connect to Remote Camera):
1. Tap "Connect"
2. Enter the 6-character pairing code
3. Tap "Connect"
4. View the remote camera feed
5. Tap "Capture" to take a photo (coming soon)
6. Tap "Disconnect" when done

## Project Structure

```
lib/
├── config/
│   └── app_config.dart          # App configuration
├── screens/
│   ├── share_camera_screen.dart # Share camera UI
│   ├── connect_camera_screen.dart # Connect to remote camera UI
│   └── remote_camera_view_screen.dart # Remote camera view UI
├── services/
│   ├── signaling_service.dart   # WebSocket signaling
│   ├── camera_stream_service.dart # WebRTC peer connections
│   └── remote_camera_manager.dart # Orchestrates streaming
├── utils/
│   ├── error_handler.dart       # Error handling utilities
│   └── connection_monitor.dart  # Connection quality monitoring
└── main.dart                    # App entry point

signaling-server/
├── index.js                     # Signaling server
├── package.json                 # Node.js dependencies
└── README.md                    # Server documentation
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
