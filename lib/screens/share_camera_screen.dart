import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/remote_camera_manager.dart' hide RemoteConnectionState;
import '../services/remote_camera_manager.dart' as remote;
import 'dart:async';

class ShareCameraScreen extends StatefulWidget {
  final String serverUrl;

  const ShareCameraScreen({
    Key? key,
    required this.serverUrl,
  }) : super(key: key);

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

    // Request permissions
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Camera and microphone permissions are required';
      });
      _showErrorDialog('Permissions Required',
          'Please grant camera and microphone permissions in settings.');
      return;
    }

    try {
      setState(() {
        _statusMessage = 'Starting camera...';
      });

      // Set up connection state callback
      _manager.onConnectionStateChanged = (state) {
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

      // Set up peer disconnected callback
      _manager.onPeerDisconnected = () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receiver disconnected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      };

      // Start sharing
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

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    setState(() {
      _connectionDuration = '00:00';
    });
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
    _stopDurationTimer();
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
                // Camera preview
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
                
                // Pairing code section
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
                
                // Status section
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _manager.connectionState == remote.RemoteConnectionState.connected
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
                          Text(
                            _statusMessage,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      if (_manager.connectionState == remote.RemoteConnectionState.connected)
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
                
                // Control buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isSharing ? _switchCamera : null,
                        icon: const Icon(Icons.flip_camera_android),
                        label: const Text('Switch Camera'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _stopSharing,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop Sharing'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
