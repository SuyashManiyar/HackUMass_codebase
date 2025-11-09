import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/remote_camera_manager.dart' hide RemoteConnectionState;
import '../../services/remote_camera_manager.dart' as remote;

class ShareCameraScreen extends StatefulWidget {
  const ShareCameraScreen({
    super.key,
    required this.serverUrl,
  });

  final String serverUrl;

  @override
  State<ShareCameraScreen> createState() => _ShareCameraScreenState();
}

class _ShareCameraScreenState extends State<ShareCameraScreen> {
  final RemoteCameraManager _manager = RemoteCameraManager();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  String? _pairingCode;
  bool _isLoading = false;
  bool _isSharing = false;
  String _statusMessage = '';
  DateTime? _connectedAt;
  Timer? _durationTimer;
  String _connectionDuration = '00:00';
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _startSharing();
  }

  Future<void> _initializeRenderer() async {
    await _localRenderer.initialize();
  }

  Future<void> _startSharing() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting permissions...';
    });

    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Camera and microphone permissions are required';
      });
      _showErrorDialog(
        'Permissions Required',
        'Please grant camera and microphone permissions in settings.',
      );
      return;
    }

    try {
      setState(() {
        _statusMessage = 'Starting camera...';
      });

      _manager.onConnectionStateChanged = (state) {
        if (!mounted) return;
        setState(() {
          if (state == remote.RemoteConnectionState.connected) {
            _statusMessage = 'Connected';
            _connectedAt = DateTime.now();
            _startDurationTimer();
          } else if (state == remote.RemoteConnectionState.connecting) {
            _statusMessage = 'Waiting for receiver...';
          } else if (state == remote.RemoteConnectionState.failed) {
            _statusMessage = 'Connection failed';
          } else if (state == remote.RemoteConnectionState.disconnected) {
            _statusMessage = 'Disconnected';
            _stopDurationTimer();
          }
        });
      };

      _manager.onPeerDisconnected = () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receiver disconnected'),
            backgroundColor: Colors.orange,
          ),
        );
      };

      final pairingCode = await _manager.startSharing(
        serverUrl: widget.serverUrl,
        useFrontCamera: false,
      );

      setState(() {
        _pairingCode = pairingCode;
        _isSharing = true;
        _isLoading = false;
        _statusMessage = 'Waiting for receiver...';
        _localRenderer.srcObject = _manager.localStream;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: ${e.toString()}';
      });
      _showErrorDialog('Error', 'Failed to start sharing: ${e.toString()}');
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_connectedAt != null && mounted) {
        final duration = DateTime.now().difference(_connectedAt!);
        setState(() {
          _connectionDuration = _formatDuration(duration);
        });
      }
    });
  }

  void _stopDurationTimer({bool updateUi = true}) {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    if (updateUi && mounted) {
      setState(() {
        _connectionDuration = '00:00';
      });
    } else {
      _connectionDuration = '00:00';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _switchCamera() async {
    try {
      await _manager.switchCamera();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera switched'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      _showErrorDialog('Error', 'Failed to switch camera: ${e.toString()}');
    }
  }

  Future<void> _stopSharing() async {
    try {
      await _manager.stop();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showErrorDialog('Error', 'Failed to stop sharing: ${e.toString()}');
    }
  }

  Future<void> _captureLocalFrame() async {
    if (_isCapturing || !_isSharing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final file = await _manager.captureLocalFrame();
      if (!mounted) return;
      final destinationMessage = (Platform.isIOS || Platform.isAndroid)
          ? 'Saved to Photos'
          : 'Saved to ${file.path}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Frame captured! $destinationMessage'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      } else {
        _isCapturing = false;
      }
    }
  }

  void _copyPairingCode() {
    if (_pairingCode != null) {
      Clipboard.setData(ClipboardData(text: _pairingCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pairing code copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopDurationTimer(updateUi: false);
    _localRenderer.dispose();
    _manager.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share Camera'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    color: Colors.black,
                    child: _isSharing
                        ? RTCVideoView(_localRenderer, mirror: true)
                        : const Center(
                            child: Text(
                              'Camera not available',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Column(
                    children: [
                      const Text(
                        'Pairing Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_pairingCode != null)
                        GestureDetector(
                          onTap: _copyPairingCode,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _pairingCode!,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 4,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.copy, size: 20),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        const Text('Generating...'),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to copy',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _manager.connectionState ==
                                    remote.RemoteConnectionState.connected
                                ? Icons.check_circle
                                : _manager.connectionState ==
                                        remote.RemoteConnectionState.connecting
                                    ? Icons.hourglass_empty
                                    : Icons.error,
                            color: _manager.connectionState ==
                                    remote.RemoteConnectionState.connected
                                ? Colors.green
                                : _manager.connectionState ==
                                        remote.RemoteConnectionState.connecting
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _statusMessage,
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      if (_manager.connectionState ==
                          remote.RemoteConnectionState.connected)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Duration: $_connectionDuration',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _manager.connectionState ==
                                          remote.RemoteConnectionState.connected &&
                                      !_isCapturing
                                  ? _captureLocalFrame
                                  : null,
                          icon: _isCapturing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _isCapturing ? 'Capturing...' : 'Capture Frame',
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSharing ? _switchCamera : null,
                          icon: const Icon(Icons.cameraswitch_outlined),
                          label: const Text('Switch Camera'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton.icon(
                    onPressed: _isSharing ? _stopSharing : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop Sharing'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}


