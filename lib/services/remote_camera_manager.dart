import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'camera_stream_service.dart';
import 'signaling_service.dart';

enum RemoteConnectionState { disconnected, connecting, connected, failed }

class RemoteCameraManager {
  final CameraStreamService _cameraService = CameraStreamService();
  final SignalingService _signalingService = SignalingService();

  RemoteConnectionState _connectionState = RemoteConnectionState.disconnected;
  MediaStream? _remoteStream;
  bool _isSender = false;

  RemoteConnectionState get connectionState => _connectionState;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _cameraService.localStream;
  bool get isSender => _isSender;

  // Callbacks
  Function(RemoteConnectionState)? onConnectionStateChanged;
  Function(MediaStream)? onRemoteStreamReceived;
  Function()? onPeerDisconnected;

  /// Start sharing camera (sender side)
  Future<String> startSharing({
    required String serverUrl,
    bool useFrontCamera = false,
  }) async {
    try {
      _isSender = true;
      _updateConnectionState(RemoteConnectionState.connecting);

      log('Connecting to signaling server...');
      await _signalingService.connect(serverUrl);

      log('Registering as sender...');
      final pairingCode = await _signalingService.registerAsSender();

      log('Initializing camera...');
      await _cameraService.initializeCamera(useFrontCamera: useFrontCamera);

      log('Creating peer connection...');
      await _cameraService.initializePeerConnection();

      log('Adding local stream...');
      await _cameraService.addLocalStream(_cameraService.localStream!);

      _cameraService.onIceCandidate((candidate) {
        _signalingService.sendIceCandidate(candidate, true);
      });

      _signalingService.onReceiverJoined(() async {
        log('Receiver joined, creating offer...');
        try {
          final offer = await _cameraService.createOffer();
          await _signalingService.sendOffer(offer);
        } catch (e) {
          log('Error creating offer: $e');
          _updateConnectionState(RemoteConnectionState.failed);
        }
      });

      _signalingService.onAnswer((answer) async {
        log('Received answer from receiver');
        try {
          await _cameraService.setRemoteDescription(answer);
          _updateConnectionState(RemoteConnectionState.connected);
        } catch (e) {
          log('Error setting remote description: $e');
          _updateConnectionState(RemoteConnectionState.failed);
        }
      });

      _signalingService.onIceCandidate((candidate) async {
        try {
          await _cameraService.addIceCandidate(candidate);
        } catch (e) {
          log('Error adding ICE candidate: $e');
        }
      });

      _signalingService.onPeerDisconnected(() {
        log('Peer disconnected');
        _updateConnectionState(RemoteConnectionState.disconnected);
        onPeerDisconnected?.call();
      });

      log('Sharing started with pairing code: $pairingCode');
      return pairingCode;
    } catch (e) {
      log('Error starting sharing: $e');
      _updateConnectionState(RemoteConnectionState.failed);
      await stop();
      rethrow;
    }
  }

  /// Connect to remote camera (receiver side)
  Future<MediaStream> connectToRemoteCamera(
    String pairingCode,
    String serverUrl,
  ) async {
    try {
      _isSender = false;
      _updateConnectionState(RemoteConnectionState.connecting);

      log('Connecting to signaling server...');
      await _signalingService.connect(serverUrl);

      log('Joining as receiver with code: $pairingCode');
      await _signalingService.joinAsReceiver(pairingCode);

      log('Creating peer connection...');
      await _cameraService.initializePeerConnection();

      _cameraService.onIceCandidate((candidate) {
        _signalingService.sendIceCandidate(candidate, false);
      });

      final remoteStreamCompleter = Completer<MediaStream>();

      _cameraService.onRemoteStream((stream) {
        log('Remote stream received');
        _remoteStream = stream;
        _updateConnectionState(RemoteConnectionState.connected);
        onRemoteStreamReceived?.call(stream);
        if (!remoteStreamCompleter.isCompleted) {
          remoteStreamCompleter.complete(stream);
        }
      });

      _signalingService.onOffer((offer) async {
        log('Received offer from sender');
        try {
          await _cameraService.setRemoteDescription(offer);
          final answer = await _cameraService.createAnswer();
          await _signalingService.sendAnswer(answer);
        } catch (e) {
          log('Error handling offer: $e');
          _updateConnectionState(RemoteConnectionState.failed);
        }
      });

      _signalingService.onIceCandidate((candidate) async {
        try {
          await _cameraService.addIceCandidate(candidate);
        } catch (e) {
          log('Error adding ICE candidate: $e');
        }
      });

      _signalingService.onPeerDisconnected(() {
        log('Peer disconnected');
        _updateConnectionState(RemoteConnectionState.disconnected);
        onPeerDisconnected?.call();
      });

      log('Waiting for remote stream...');
      final remoteStream = await remoteStreamCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Timeout waiting for remote stream');
        },
      );

      log('Connected to remote camera');
      return remoteStream;
    } catch (e) {
      log('Error connecting to remote camera: $e');
      _updateConnectionState(RemoteConnectionState.failed);
      await stop();
      rethrow;
    }
  }

  /// Capture frame from remote stream
  Future<File> captureFrame(MediaStream stream) async {
    // Implementation remains the same
    return File(''); // Placeholder
  }

  /// Switch camera (only for sender)
  Future<void> switchCamera() async {
    if (!_isSender) {
      throw Exception('Only sender can switch camera');
    }
    try {
      await _cameraService.switchCamera();
      log('Camera switched');
    } catch (e) {
      log('Error switching camera: $e');
      rethrow;
    }
  }

  /// Stop sharing or receiving
  Future<void> stop() async {
    try {
      await _signalingService.disconnect();
      await _cameraService.dispose();
      _remoteStream = null;
      _isSender = false;
      _updateConnectionState(RemoteConnectionState.disconnected);
      log('Stopped');
    } catch (e) {
      log('Error stopping: $e');
    }
  }

  void _updateConnectionState(RemoteConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      onConnectionStateChanged?.call(state);
    }
  }
}
