const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// In-memory storage for active sessions
const sessions = new Map(); // pairingCode -> { senderId, receiverId, createdAt }

// Session cleanup interval (remove sessions older than 1 hour)
const SESSION_TIMEOUT = 60 * 60 * 1000; // 1 hour
setInterval(() => {
  const now = Date.now();
  for (const [code, session] of sessions.entries()) {
    if (now - session.createdAt > SESSION_TIMEOUT) {
      console.log(`Cleaning up expired session: ${code}`);
      sessions.delete(code);
    }
  }
}, 5 * 60 * 1000); // Check every 5 minutes

// Rate limiting storage
const rateLimits = new Map(); // ip -> { count, resetTime }
const RATE_LIMIT_MAX = 10;
const RATE_LIMIT_WINDOW = 60 * 60 * 1000; // 1 hour

function checkRateLimit(ip) {
  const now = Date.now();
  const limit = rateLimits.get(ip);
  
  if (!limit || now > limit.resetTime) {
    rateLimits.set(ip, { count: 1, resetTime: now + RATE_LIMIT_WINDOW });
    return true;
  }
  
  if (limit.count >= RATE_LIMIT_MAX) {
    return false;
  }
  
  limit.count++;
  return true;
}

function generatePairingCode() {
  let code;
  do {
    code = Math.random().toString(36).substring(2, 8).toUpperCase();
  } while (sessions.has(code)); // Ensure uniqueness
  return code;
}

io.on('connection', (socket) => {
  console.log(`Client connected: ${socket.id}`);
  
  // Handle register-sender
  socket.on('register-sender', (callback) => {
    const ip = socket.handshake.address;
    
    if (!checkRateLimit(ip)) {
      console.log(`Rate limit exceeded for IP: ${ip}`);
      callback({ success: false, error: 'Rate limit exceeded. Please try again later.' });
      return;
    }
    
    const pairingCode = generatePairingCode();
    sessions.set(pairingCode, {
      senderId: socket.id,
      receiverId: null,
      createdAt: Date.now()
    });
    
    console.log(`Sender registered with code: ${pairingCode}`);
    callback({ success: true, pairingCode });
  });
  
  // Handle join-receiver
  socket.on('join-receiver', ({ pairingCode }, callback) => {
    if (!pairingCode || typeof pairingCode !== 'string') {
      callback({ success: false, error: 'Invalid pairing code format' });
      return;
    }
    
    const session = sessions.get(pairingCode.toUpperCase());
    
    if (!session) {
      console.log(`Invalid pairing code: ${pairingCode}`);
      callback({ success: false, error: 'Invalid or expired pairing code' });
      return;
    }
    
    if (session.receiverId) {
      console.log(`Pairing code already in use: ${pairingCode}`);
      callback({ success: false, error: 'This pairing code is already in use' });
      return;
    }
    
    session.receiverId = socket.id;
    console.log(`Receiver joined with code: ${pairingCode}`);
    callback({ success: true });
    
    // Notify sender that receiver has joined
    io.to(session.senderId).emit('receiver-joined');
  });
  
  // Handle offer (from sender to receiver)
  socket.on('offer', ({ pairingCode, offer }) => {
    const session = sessions.get(pairingCode);
    
    if (!session) {
      console.log(`Offer sent with invalid code: ${pairingCode}`);
      return;
    }
    
    if (session.senderId !== socket.id) {
      console.log(`Unauthorized offer attempt from: ${socket.id}`);
      return;
    }
    
    if (session.receiverId) {
      console.log(`Forwarding offer to receiver: ${session.receiverId}`);
      io.to(session.receiverId).emit('offer', { offer });
    }
  });
  
  // Handle answer (from receiver to sender)
  socket.on('answer', ({ pairingCode, answer }) => {
    const session = sessions.get(pairingCode);
    
    if (!session) {
      console.log(`Answer sent with invalid code: ${pairingCode}`);
      return;
    }
    
    if (session.receiverId !== socket.id) {
      console.log(`Unauthorized answer attempt from: ${socket.id}`);
      return;
    }
    
    console.log(`Forwarding answer to sender: ${session.senderId}`);
    io.to(session.senderId).emit('answer', { answer });
  });
  
  // Handle ICE candidates
  socket.on('ice-candidate', ({ pairingCode, candidate, isSender }) => {
    const session = sessions.get(pairingCode);
    
    if (!session) {
      console.log(`ICE candidate sent with invalid code: ${pairingCode}`);
      return;
    }
    
    // Verify the sender
    if (isSender && session.senderId !== socket.id) {
      console.log(`Unauthorized ICE candidate from sender: ${socket.id}`);
      return;
    }
    
    if (!isSender && session.receiverId !== socket.id) {
      console.log(`Unauthorized ICE candidate from receiver: ${socket.id}`);
      return;
    }
    
    const targetId = isSender ? session.receiverId : session.senderId;
    
    if (targetId) {
      console.log(`Forwarding ICE candidate to: ${targetId}`);
      io.to(targetId).emit('ice-candidate', { candidate });
    }
  });
  
  // Handle disconnect
  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);
    
    // Clean up sessions where this socket was involved
    for (const [code, session] of sessions.entries()) {
      if (session.senderId === socket.id || session.receiverId === socket.id) {
        console.log(`Cleaning up session: ${code}`);
        
        // Notify the other party
        if (session.senderId === socket.id && session.receiverId) {
          io.to(session.receiverId).emit('peer-disconnected');
        } else if (session.receiverId === socket.id && session.senderId) {
          io.to(session.senderId).emit('peer-disconnected');
        }
        
        sessions.delete(code);
      }
    }
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    activeSessions: sessions.size,
    uptime: process.uptime()
  });
});

// Get server stats
app.get('/stats', (req, res) => {
  res.json({
    activeSessions: sessions.size,
    uptime: process.uptime(),
    connections: io.engine.clientsCount
  });
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
  console.log(`Health check available at http://localhost:${PORT}/health`);
});
