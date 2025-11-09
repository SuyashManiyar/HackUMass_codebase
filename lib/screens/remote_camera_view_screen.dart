import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import '../services/remote_camera_manager.dart' as remote;

class RemoteCameraViewScreen extends StatefulWidget {
  final remote.RemoteCameraManager manager;
  final String pairingCode;

  const RemoteCameraViewScreen({
    Key? key,
    required this.manager,
    required this.pairingCode,
  }) : super(key: key);

  @override
  State<RemoteCameraViewScreen> createState() => _RemoteCameraViewScreenState();
}

class _RemoteCameraViewScreenState extends State<RemoteCameraViewScreen> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  DateTime? _connectedAt;
  Timer? _durationTimer;
  String _connectionDuration = '00:00';
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _setupCallbacks();
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
    if (widget.manager.remoteStream != null) {
      setState(() {
        _remoteRenderer.srcObject = widget.manager.remoteStream;
        _connectedAt = DateTime.now();
        _startDurationTimer();
      });
    }
  }

  void _setupCallbacks() {
    widget.manager.onRemoteStreamReceived = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _connectedAt = DateTime.now();
          _startDurationTimer();
        });
      }
    };

    widget.manager.onPeerDisconnected = () {
      if (mounted) {
        _showDisconnectedDialog();
      }
    };

    widget.manager.onConnectionStateChanged = (state) {
      if (mounted && state == remote.RemoteConnectionState.failed) {
        _showDisconnectedDialog();
      }
    };
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

  Future<void> _captureFrame() async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      if (widget.manager.remoteStream == null) {
        throw Exception('No remote stream available');
      }

      // Capture frame from remote stream
      final file = await widget.manager.captureFrame(widget.manager.remoteStream!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Frame captured! Saved to: ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
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
      setState(() {
        _isCapturing = false;
      });
    }
  }

  Future<void> _disconnect() async {
    try {
      await widget.manager.stop();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error disconnecting: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDisconnectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Disconnected'),
        content: const Text('The remote camera has been disconnected.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopDurationTimer();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.manager.connectionState == remote.RemoteConnectionState.connected;
    final connectionQuality = isConnected ? 'Good' : 'Poor';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Camera'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Connection Info'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pairing Code: ${widget.pairingCode}'),
                      const SizedBox(height: 8),
                      Text('Status: ${isConnected ? 'Connected' : 'Connecting'}'),
                      const SizedBox(height: 8),
                      Text('Duration: $_connectionDuration'),
                      const SizedBox(height: 8),
                      Text('Quality: $connectionQuality'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: widget.manager.remoteStream != null
                  ? RTCVideoView(_remoteRenderer)
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Waiting for video stream...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[100],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isConnected ? Icons.check_circle : Icons.hourglass_empty,
                        color: isConnected ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isConnected ? 'Connected' : 'Connecting...',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.signal_cellular_alt,
                        color: isConnected ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          connectionQuality,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    _connectionDuration,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isConnected && !_isCapturing ? _captureFrame : null,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: const Text('Capture'),
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
                    onPressed: _disconnect,
                    icon: const Icon(Icons.close),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
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
