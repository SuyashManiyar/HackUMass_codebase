import 'package:flutter_webrtc/flutter_webrtc.dart';

class CameraStreamService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isFrontCamera = false;

  // Callbacks
  Function(RTCIceCandidate)? _onIceCandidateCallback;
  Function(MediaStream)? _onRemoteStreamCallback;

  MediaStream? get localStream => _localStream;
  RTCPeerConnection? get peerConnection => _peerConnection;

  /// Initialize camera and create local stream
  Future<MediaStream> initializeCamera({bool useFrontCamera = false}) async {
    try {
      _isFrontCamera = useFrontCamera;

      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': useFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      };

      _localStream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
      print('Camera initialized: ${useFrontCamera ? 'front' : 'back'}');

      return _localStream!;
    } catch (e) {
      print('Error initializing camera: $e');
      rethrow;
    }
  }

  /// Create WebRTC peer connection
  Future<RTCPeerConnection> initializePeerConnection() async {
    try {
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(configuration);

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        print('New ICE candidate: ${candidate.candidate}');
        if (_onIceCandidateCallback != null) {
          _onIceCandidateCallback!(candidate);
        }
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('Remote track received');
        if (event.streams.isNotEmpty) {
          final remoteStream = event.streams[0];
          if (_onRemoteStreamCallback != null) {
            _onRemoteStreamCallback!(remoteStream);
          }
        }
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('Connection state: $state');
      };

      // Handle ICE connection state changes
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('ICE connection state: $state');
      };

      print('Peer connection created');
      return _peerConnection!;
    } catch (e) {
      print('Error creating peer connection: $e');
      rethrow;
    }
  }

  /// Add local stream to peer connection
  Future<void> addLocalStream(MediaStream stream) async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    try {
      stream.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, stream);
      });
      print('Local stream added to peer connection');
    } catch (e) {
      print('Error adding local stream: $e');
      rethrow;
    }
  }

  /// Set callback for ICE candidates
  void onIceCandidate(Function(RTCIceCandidate) callback) {
    _onIceCandidateCallback = callback;
  }

  /// Set callback for remote stream
  void onRemoteStream(Function(MediaStream) callback) {
    _onRemoteStreamCallback = callback;
  }

  /// Create offer (for sender)
  Future<RTCSessionDescription> createOffer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': true,
      });

      await _peerConnection!.setLocalDescription(offer);
      print('Offer created and set as local description');

      return offer;
    } catch (e) {
      print('Error creating offer: $e');
      rethrow;
    }
  }

  /// Create answer (for receiver)
  Future<RTCSessionDescription> createAnswer() async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    try {
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': true,
      });

      await _peerConnection!.setLocalDescription(answer);
      print('Answer created and set as local description');

      return answer;
    } catch (e) {
      print('Error creating answer: $e');
      rethrow;
    }
  }

  /// Set remote description
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    try {
      await _peerConnection!.setRemoteDescription(description);
      print('Remote description set');
    } catch (e) {
      print('Error setting remote description: $e');
      rethrow;
    }
  }

  /// Add ICE candidate
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) {
      throw Exception('Peer connection not initialized');
    }

    try {
      await _peerConnection!.addCandidate(candidate);
      print('ICE candidate added');
    } catch (e) {
      print('Error adding ICE candidate: $e');
      rethrow;
    }
  }

  /// Switch camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream == null) {
      throw Exception('Local stream not initialized');
    }

    try {
      // Get the video track
      final videoTrack = _localStream!.getVideoTracks().first;

      // Use Helper to switch camera
      await Helper.switchCamera(videoTrack);

      _isFrontCamera = !_isFrontCamera;
      print('Camera switched to: ${_isFrontCamera ? 'front' : 'back'}');
    } catch (e) {
      print('Error switching camera: $e');
      rethrow;
    }
  }

  /// Stop streaming and cleanup
  Future<void> dispose() async {
    try {
      // Stop all tracks in local stream
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _localStream = null;

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Clear callbacks
      _onIceCandidateCallback = null;
      _onRemoteStreamCallback = null;

      print('Camera stream service disposed');
    } catch (e) {
      print('Error disposing camera stream service: $e');
    }
  }
}
