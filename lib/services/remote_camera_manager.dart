import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';

import 'camera_stream_service.dart';
import 'renderer_frame_capture_stub.dart'
    if (dart.library.io) 'renderer_frame_capture_io.dart';
import 'signaling_service.dart';

enum RemoteConnectionState { disconnected, connecting, connected, failed }

class RemoteCameraManager {
  final CameraStreamService _cameraService = CameraStreamService();
  final SignalingService _signalingService = SignalingService();

  RemoteConnectionState _connectionState = RemoteConnectionState.disconnected;
  MediaStream? _remoteStream;
  bool _isSender = false;
  RTCDataChannel? _captureChannel;

  RemoteConnectionState get connectionState => _connectionState;
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _cameraService.localStream;
  bool get isSender => _isSender;

  // Callbacks
  Function(RemoteConnectionState)? onConnectionStateChanged;
  Function(MediaStream)? onRemoteStreamReceived;
  Function()? onPeerDisconnected;
  Function(File file)? onRemoteCaptureSaved;

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

      await _setupCaptureDataChannel(isSender: true);

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

      _cameraService.onDataChannel((channel) {
        if (channel.label == 'capture') {
          _captureChannel = channel;
          _captureChannel!.onMessage = (message) {
            if (message.isBinary) {
              _handleIncomingCapture(message.binary);
            }
          };
        }
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

      await _setupCaptureDataChannel(isSender: false);

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
    if (kIsWeb) {
      throw UnsupportedError('Frame capture is not supported on web with flutter_webrtc');
    }

    RTCVideoRenderer? renderer;
    try {
      // Create RTCVideoRenderer to capture frame
      renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;

      // Wait for the renderer to have a frame
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if we have valid video dimensions
      final videoWidth = renderer.videoWidth;
      final videoHeight = renderer.videoHeight;

      if (videoWidth == 0 || videoHeight == 0) {
        throw Exception('No video frame available');
      }

      final imageData = await captureRendererFrame(renderer);
      final file = await _persistCapture(imageData,
          prefix: 'remote_capture', isLocalCapture: false);

      log('Frame captured: ${file.path}');
      return file;
    } catch (e) {
      log('Error capturing frame: $e');
      rethrow;
    } finally {
      await renderer?.dispose();
    }
  }

  Future<File> captureLocalFrame() async {
    if (kIsWeb) {
      throw UnsupportedError('Local frame capture is not supported on web');
    }

    final stream = _cameraService.localStream;
    if (stream == null) {
      throw StateError('Local stream is not available');
    }

    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) {
      throw StateError('No video track available to capture');
    }

    try {
      final frameBuffer = await videoTracks.first.captureFrame();
      final bytes = frameBuffer.asUint8List();
      final file = await _persistCapture(bytes,
          prefix: 'local_capture', isLocalCapture: true);

      if (_captureChannel != null &&
          _captureChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        _captureChannel!
            .send(RTCDataChannelMessage.fromBinary(bytes));
      }

      if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
        await ImageGallerySaver.saveImage(bytes,
            name: 'HackUMass_${DateTime.now().millisecondsSinceEpoch}');
      }
      log('Local frame captured: ${file.path}');
      return file;
    } catch (e) {
      log('Error capturing local frame: $e');
      rethrow;
    }
  }

  Future<File> _persistCapture(Uint8List bytes,
      {required String prefix, required bool isLocalCapture}) async {
    final directory = await _resolveCaptureDirectory(isLocalCapture: isLocalCapture);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final suffix = isLocalCapture ? 'phone' : 'remote';
    final filePath = '${directory.path}/${prefix}_${suffix}_$timestamp.jpg';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _setupCaptureDataChannel({required bool isSender}) async {
    if (isSender) {
      _captureChannel = await _cameraService.createDataChannel('capture');
      _captureChannel?.onMessage = (message) {
        if (message.isBinary) {
          _handleIncomingCapture(message.binary);
        }
      };
    }
  }

  void _handleIncomingCapture(Uint8List data) {
    unawaited(() async {
      try {
        final file = await _persistCapture(data,
            prefix: 'remote_capture', isLocalCapture: false);
        log('Incoming capture saved: ${file.path}');
        onRemoteCaptureSaved?.call(file);
      } catch (e) {
        log('Error saving incoming capture: $e');
      }
    }());
  }

  Future<Directory> _resolveCaptureDirectory({required bool isLocalCapture}) async {
    Directory? target;

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        target = downloads;
      }
    }

    target ??= await getApplicationDocumentsDirectory();

    final folderName = isLocalCapture ? 'HackUMassCaptures/local' : 'HackUMassCaptures/remote';
    final directory = Directory('${target.path}/$folderName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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
      await _captureChannel?.close();
      _captureChannel = null;
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
