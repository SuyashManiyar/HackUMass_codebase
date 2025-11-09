# Design Document: Remote Camera Feed

## Overview

This feature adds real-time camera feed sharing capabilities to the HackUMass Flutter application using WebRTC for peer-to-peer video streaming. The solution consists of two main components:

1. **Flutter Mobile Application**: Enhanced with camera streaming and receiving capabilities
2. **Node.js Signaling Server**: Lightweight WebSocket server for connection coordination

The architecture follows a peer-to-peer model where video data flows directly between devices after the initial signaling handshake, ensuring low latency and privacy.

## Architecture

### High-Level Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Camera Source  │         │  Receiver       │
│  Device         │         │  Device         │
│  (Flutter App)  │         │  (Flutter App)  │
└────────┬────────┘         └────────┬────────┘
         │                           │
         │  WebSocket (Signaling)    │
         │                           │
         └──────────┬────────────────┘
                    │
         ┌──────────▼──────────┐
         │  Signaling Server   │
         │  (Node.js/Socket.io)│
         └─────────────────────┘
         
         After Connection:
         
┌─────────────────┐                 ┌─────────────────┐
│  Camera Source  │◄───────────────►│  Receiver       │
│  Device         │  WebRTC P2P     │  Device         │
└─────────────────┘  Video Stream   └─────────────────┘
```

### Technology Stack

**Flutter Application:**
- `flutter_webrtc`: WebRTC implementation for Flutter
- `socket_io_client`: WebSocket client for signaling
- `camera`: Camera access and control
- `permission_handler`: Runtime permissions management

**Signaling Server:**
- Node.js with Express
- Socket.io for WebSocket communication
- Simple in-memory storage for pairing codes

## Components and Interfaces

### 1. Flutter Application Components

#### 1.1 Camera Stream Service (`lib/services/camera_stream_service.dart`)

Manages camera access and WebRTC peer connections.

```dart
class CameraStreamService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  
  // Initialize camera and create local stream
  Future<MediaStream> initializeCamera({bool useFrontCamera = false});
  
  // Create WebRTC peer connection
  Future<RTCPeerConnection> createPeerConnection();
  
  // Add local stream to peer connection
  Future<void> addLocalStream(MediaStream stream);
  
  // Handle ICE candidates
  void onIceCandidate(Function(RTCIceCandidate) callback);
  
  // Create offer (for sender)
  Future<RTCSessionDescription> createOffer();
  
  // Create answer (for receiver)
  Future<RTCSessionDescription> createAnswer();
  
  // Set remote description
  Future<void> setRemoteDescription(RTCSessionDescription description);
  
  // Add ICE candidate
  Future<void> addIceCandidate(RTCIceCandidate candidate);
  
  // Switch camera (front/back)
  Future<void> switchCamera();
  
  // Stop streaming and cleanup
  Future<void> dispose();
}
```

#### 1.2 Signaling Service (`lib/services/signaling_service.dart`)

Handles WebSocket communication with the signaling server.

```dart
class SignalingService {
  IO.Socket? _socket;
  String? _pairingCode;
  
  // Connect to signaling server
  Future<void> connect(String serverUrl);
  
  // Register as sender and get pairing code
  Future<String> registerAsSender();
  
  // Join as receiver with pairing code
  Future<void> joinAsReceiver(String pairingCode);
  
  // Send WebRTC offer
  Future<void> sendOffer(RTCSessionDescription offer);
  
  // Send WebRTC answer
  Future<void> sendAnswer(RTCSessionDescription answer);
  
  // Send ICE candidate
  Future<void> sendIceCandidate(RTCIceCandidate candidate);
  
  // Listen for offers
  void onOffer(Function(RTCSessionDescription) callback);
  
  // Listen for answers
  void onAnswer(Function(RTCSessionDescription) callback);
  
  // Listen for ICE candidates
  void onIceCandidate(Function(RTCIceCandidate) callback);
  
  // Disconnect and cleanup
  Future<void> disconnect();
}
```

#### 1.3 Remote Camera Manager (`lib/services/remote_camera_manager.dart`)

Orchestrates the camera streaming workflow by coordinating the camera stream and signaling services.

```dart
class RemoteCameraManager {
  final CameraStreamService _cameraService;
  final SignalingService _signalingService;
  
  // Start sharing camera (sender side)
  Future<String> startSharing({String serverUrl});
  
  // Connect to remote camera (receiver side)
  Future<MediaStream> connectToRemoteCamera(String pairingCode, String serverUrl);
  
  // Capture frame from remote stream
  Future<File> captureFrame(MediaStream remoteStream);
  
  // Stop sharing or receiving
  Future<void> stop();
}
```

#### 1.4 UI Screens

**Share Camera Screen** (`lib/screens/share_camera_screen.dart`)
- Display camera preview
- Show generated pairing code (large, easy to read)
- Camera switch button
- Stop sharing button
- Connection status indicator

**Connect to Camera Screen** (`lib/screens/connect_camera_screen.dart`)
- Pairing code input field
- Connect button
- Connection status feedback

**Remote Camera View Screen** (`lib/screens/remote_camera_view_screen.dart`)
- Display remote camera feed
- Capture button
- Disconnect button
- Connection quality indicator

### 2. Signaling Server Components

#### 2.1 Server Structure (`server/index.js`)

```javascript
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

// In-memory storage for active sessions
const sessions = new Map(); // pairingCode -> { senderId, receiverId }

io.on('connection', (socket) => {
  // Handle register-sender
  socket.on('register-sender', (callback) => {
    const pairingCode = generatePairingCode();
    sessions.set(pairingCode, { senderId: socket.id, receiverId: null });
    callback({ pairingCode });
  });
  
  // Handle join-receiver
  socket.on('join-receiver', ({ pairingCode }, callback) => {
    const session = sessions.get(pairingCode);
    if (session && !session.receiverId) {
      session.receiverId = socket.id;
      callback({ success: true });
    } else {
      callback({ success: false, error: 'Invalid or expired code' });
    }
  });
  
  // Handle offer
  socket.on('offer', ({ pairingCode, offer }) => {
    const session = sessions.get(pairingCode);
    if (session && session.receiverId) {
      io.to(session.receiverId).emit('offer', { offer });
    }
  });
  
  // Handle answer
  socket.on('answer', ({ pairingCode, answer }) => {
    const session = sessions.get(pairingCode);
    if (session && session.senderId) {
      io.to(session.senderId).emit('answer', { answer });
    }
  });
  
  // Handle ICE candidates
  socket.on('ice-candidate', ({ pairingCode, candidate, isSender }) => {
    const session = sessions.get(pairingCode);
    if (session) {
      const targetId = isSender ? session.receiverId : session.senderId;
      if (targetId) {
        io.to(targetId).emit('ice-candidate', { candidate });
      }
    }
  });
  
  // Handle disconnect
  socket.on('disconnect', () => {
    // Clean up sessions where this socket was involved
    for (const [code, session] of sessions.entries()) {
      if (session.senderId === socket.id || session.receiverId === socket.id) {
        sessions.delete(code);
      }
    }
  });
});

function generatePairingCode() {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
}

server.listen(3000, () => {
  console.log('Signaling server running on port 3000');
});
```

## Data Models

### Pairing Session

```dart
class PairingSession {
  final String pairingCode;
  final String senderId;
  final String? receiverId;
  final DateTime createdAt;
  
  PairingSession({
    required this.pairingCode,
    required this.senderId,
    this.receiverId,
    required this.createdAt,
  });
}
```

### Connection State

```dart
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  failed,
}

class ConnectionStatus {
  final ConnectionState state;
  final String? message;
  final DateTime? connectedAt;
  
  ConnectionStatus({
    required this.state,
    this.message,
    this.connectedAt,
  });
}
```

## Error Handling

### Flutter Application

1. **Camera Access Errors**
   - Check permissions before accessing camera
   - Show user-friendly error messages for denied permissions
   - Provide guidance to enable permissions in settings

2. **Connection Errors**
   - Timeout after 30 seconds if connection not established
   - Retry logic for signaling server connection (3 attempts)
   - Clear error messages for invalid pairing codes

3. **WebRTC Errors**
   - Handle ICE connection failures
   - Detect and notify on connection quality degradation
   - Automatic reconnection attempt on connection loss

4. **Network Errors**
   - Detect when signaling server is unreachable
   - Show offline status indicator
   - Queue messages when temporarily disconnected

### Signaling Server

1. **Invalid Pairing Codes**
   - Return error response for non-existent codes
   - Validate code format before lookup

2. **Session Cleanup**
   - Remove expired sessions (older than 1 hour)
   - Clean up on socket disconnect

3. **Rate Limiting**
   - Limit pairing code generation to prevent abuse
   - Maximum 10 codes per IP per hour

## Testing Strategy

### Unit Tests

1. **CameraStreamService Tests**
   - Test camera initialization
   - Test peer connection creation
   - Test ICE candidate handling
   - Test camera switching

2. **SignalingService Tests**
   - Test WebSocket connection
   - Test message sending/receiving
   - Test reconnection logic

3. **RemoteCameraManager Tests**
   - Test sender workflow
   - Test receiver workflow
   - Test frame capture

### Integration Tests

1. **End-to-End Connection Flow**
   - Test complete sender-receiver pairing
   - Test WebRTC connection establishment
   - Test video stream transmission

2. **Error Scenarios**
   - Test invalid pairing code handling
   - Test connection timeout
   - Test network disconnection recovery

3. **Camera Operations**
   - Test camera switching during active stream
   - Test frame capture from remote stream

### Manual Testing

1. **Two-Device Testing**
   - Test on actual Android/iOS devices
   - Verify video quality and latency
   - Test on different network conditions (WiFi, cellular)

2. **UI/UX Testing**
   - Verify pairing code readability
   - Test connection status indicators
   - Verify error message clarity

## Security Considerations

1. **WebRTC Encryption**: All video data is encrypted using DTLS-SRTP (built into WebRTC)
2. **Pairing Code Expiration**: Codes expire after 1 hour or after first use
3. **No Video Storage**: Signaling server never stores or routes video data
4. **Permission Checks**: Explicit camera permission required before streaming
5. **User Consent**: Clear UI indicating when camera is being shared

## Performance Considerations

1. **Video Quality**: Default to 720p at 30fps, adjustable based on network conditions
2. **Latency Target**: < 500ms end-to-end latency
3. **Bandwidth**: Approximately 1-2 Mbps for 720p stream
4. **Battery Impact**: Monitor and optimize camera/encoding battery usage
5. **Memory Management**: Properly dispose of streams and connections

## Deployment

### Signaling Server Deployment

- Deploy to cloud platform (Heroku, AWS, Google Cloud)
- Use environment variables for configuration
- Enable HTTPS/WSS for production
- Set up monitoring and logging

### Flutter App Configuration

- Store signaling server URL in configuration
- Support multiple server endpoints for redundancy
- Allow server URL override for development/testing
