import 'package:flutter/material.dart';

import '../../services/remote_camera_manager.dart' as remote;
import 'remote_camera_view_screen.dart';

class ConnectCameraScreen extends StatefulWidget {
  const ConnectCameraScreen({
    super.key,
    required this.serverUrl,
  });

  final String serverUrl;

  @override
  State<ConnectCameraScreen> createState() => _ConnectCameraScreenState();
}

class _ConnectCameraScreenState extends State<ConnectCameraScreen> {
  final TextEditingController _pairingCodeController = TextEditingController();
  final remote.RemoteCameraManager _manager = remote.RemoteCameraManager();

  bool _isConnecting = false;
  String _errorMessage = '';

  Future<void> _connect() async {
    final pairingCode = _pairingCodeController.text.trim().toUpperCase();

    if (pairingCode.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a pairing code';
      });
      return;
    }

    if (pairingCode.length != 6) {
      setState(() {
        _errorMessage = 'Pairing code must be 6 characters';
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = '';
    });

    try {
      await _manager.connectToRemoteCamera(
        pairingCode,
        widget.serverUrl,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RemoteCameraViewScreen(
              manager: _manager,
              pairingCode: pairingCode,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _errorMessage = _getErrorMessage(e.toString());
      });
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('Invalid or expired')) {
      return 'Invalid or expired pairing code';
    } else if (error.contains('already in use')) {
      return 'This pairing code is already in use';
    } else if (error.contains('Timeout')) {
      return 'Connection timeout. Please try again.';
    } else if (error.contains('signaling server')) {
      return 'Cannot connect to server. Please check your internet connection.';
    } else {
      return 'Connection failed. Please try again.';
    }
  }

  @override
  void dispose() {
    _pairingCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Remote Camera'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.videocam,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 32),
            const Text(
              'Enter Pairing Code',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-character code from the device sharing its camera',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pairingCodeController,
              decoration: InputDecoration(
                labelText: 'Pairing Code',
                hintText: 'ABC123',
                prefixIcon: const Icon(Icons.qr_code),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 4,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              enabled: !_isConnecting,
              onChanged: (value) {
                if (_errorMessage.isNotEmpty) {
                  setState(() {
                    _errorMessage = '';
                  });
                }
              },
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _connect,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.link),
              label: Text(
                _isConnecting ? 'Connecting...' : 'Connect',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isConnecting) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Connecting to remote camera...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


