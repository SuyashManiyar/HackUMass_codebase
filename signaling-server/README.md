# HackUMass Signaling Server

WebRTC signaling server for the HackUMass camera feed sharing feature. This server facilitates the initial connection handshake between devices using WebSocket communication.

## Features

- Pairing code generation for device connections
- WebRTC signaling (offer/answer/ICE candidate exchange)
- Session management with automatic cleanup
- Rate limiting to prevent abuse
- Health check and stats endpoints

## Prerequisites

- Node.js (v14 or higher)
- npm or yarn

## Installation

1. Navigate to the signaling-server directory:
```bash
cd signaling-server
```

2. Install dependencies:
```bash
npm install
```

## Running the Server

### Development Mode (with auto-reload)
```bash
npm run dev
```

### Production Mode
```bash
npm start
```

The server will start on port 3000 by default. You can change this by setting the `PORT` environment variable:

```bash
PORT=8080 npm start
```

## API Endpoints

### Health Check
```
GET /health
```
Returns server status and active session count.

### Stats
```
GET /stats
```
Returns detailed server statistics including active sessions, uptime, and connection count.

## WebSocket Events

### Client to Server

#### `register-sender`
Register as a camera source device and receive a pairing code.

**Callback Response:**
```javascript
{
  success: true,
  pairingCode: "ABC123"
}
```

#### `join-receiver`
Join an existing session using a pairing code.

**Payload:**
```javascript
{
  pairingCode: "ABC123"
}
```

**Callback Response:**
```javascript
{
  success: true
}
```

#### `offer`
Send WebRTC offer from sender to receiver.

**Payload:**
```javascript
{
  pairingCode: "ABC123",
  offer: { /* RTCSessionDescription */ }
}
```

#### `answer`
Send WebRTC answer from receiver to sender.

**Payload:**
```javascript
{
  pairingCode: "ABC123",
  answer: { /* RTCSessionDescription */ }
}
```

#### `ice-candidate`
Send ICE candidate to peer.

**Payload:**
```javascript
{
  pairingCode: "ABC123",
  candidate: { /* RTCIceCandidate */ },
  isSender: true // or false
}
```

### Server to Client

#### `receiver-joined`
Notifies sender that a receiver has joined the session.

#### `offer`
Forwards WebRTC offer to receiver.

**Payload:**
```javascript
{
  offer: { /* RTCSessionDescription */ }
}
```

#### `answer`
Forwards WebRTC answer to sender.

**Payload:**
```javascript
{
  answer: { /* RTCSessionDescription */ }
}
```

#### `ice-candidate`
Forwards ICE candidate to peer.

**Payload:**
```javascript
{
  candidate: { /* RTCIceCandidate */ }
}
```

#### `peer-disconnected`
Notifies when the other peer disconnects.

## Configuration

### Session Timeout
Sessions expire after 1 hour of inactivity. This can be modified in `index.js`:
```javascript
const SESSION_TIMEOUT = 60 * 60 * 1000; // 1 hour in milliseconds
```

### Rate Limiting
Maximum 10 pairing code generations per IP per hour. Modify in `index.js`:
```javascript
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW = 60 * 60 * 1000; // 1 hour
```

## Deployment

### Local Network Testing
For testing on local network, find your computer's IP address:

**Windows:**
```bash
ipconfig
```

**Mac/Linux:**
```bash
ifconfig
```

Use this IP address in your Flutter app configuration (e.g., `http://192.168.1.100:3000`).

### Cloud Deployment

#### Heroku
```bash
heroku create hackumass-signaling
git push heroku main
```

#### AWS/Google Cloud/Azure
Deploy as a standard Node.js application. Ensure:
- Port is configurable via environment variable
- WebSocket connections are supported
- CORS is properly configured

## Security Notes

- Video data never passes through this server (peer-to-peer only)
- Pairing codes are single-use and expire after 1 hour
- Rate limiting prevents abuse
- For production, enable HTTPS/WSS

## Troubleshooting

### Port Already in Use
If port 3000 is already in use, specify a different port:
```bash
PORT=3001 npm start
```

### Connection Issues
- Ensure firewall allows connections on the specified port
- Check that CORS is properly configured for your client origin
- Verify WebSocket support is enabled

### Session Not Found
- Pairing codes expire after 1 hour
- Codes are single-use (one receiver per sender)
- Codes are case-insensitive but stored in uppercase

## Monitoring

Check server health:
```bash
curl http://localhost:3000/health
```

View statistics:
```bash
curl http://localhost:3000/stats
```

## License

MIT
