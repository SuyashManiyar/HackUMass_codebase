import 'dart:async';
import 'dart:ui';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum ConnectionQuality {
  excellent,
  good,
  fair,
  poor,
  disconnected,
}

class ConnectionMonitor {
  RTCPeerConnection? _peerConnection;
  Timer? _monitorTimer;
  ConnectionQuality _currentQuality = ConnectionQuality.disconnected;
  
  Function(ConnectionQuality)? onQualityChanged;

  ConnectionQuality get currentQuality => _currentQuality;

  /// Start monitoring connection quality
  void startMonitoring(RTCPeerConnection peerConnection) {
    _peerConnection = peerConnection;
    
    // Monitor connection state
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      _updateQualityFromState(state);
    };

    // Monitor ICE connection state
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _updateQualityFromIceState(state);
    };

    // Periodic quality check based on stats
    _monitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkConnectionStats();
    });
  }

  void _updateQualityFromState(RTCPeerConnectionState state) {
    ConnectionQuality newQuality;
    
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        newQuality = ConnectionQuality.good;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        newQuality = ConnectionQuality.fair;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        newQuality = ConnectionQuality.disconnected;
        break;
      default:
        newQuality = ConnectionQuality.fair;
    }

    _updateQuality(newQuality);
  }

  void _updateQualityFromIceState(RTCIceConnectionState state) {
    ConnectionQuality newQuality;
    
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        newQuality = ConnectionQuality.good;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
      case RTCIceConnectionState.RTCIceConnectionStateNew:
        newQuality = ConnectionQuality.fair;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        newQuality = ConnectionQuality.poor;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        newQuality = ConnectionQuality.disconnected;
        break;
      default:
        newQuality = ConnectionQuality.fair;
    }

    _updateQuality(newQuality);
  }

  Future<void> _checkConnectionStats() async {
    if (_peerConnection == null) return;

    try {
      // Get connection statistics
      final stats = await _peerConnection!.getStats();
      
      // Analyze stats to determine quality
      // This is a simplified version - in production you'd analyze
      // packet loss, jitter, RTT, etc.
      
      // For now, we rely on connection state
      // In a full implementation, you would parse the stats and calculate quality
    } catch (e) {
      print('Error checking connection stats: $e');
    }
  }

  void _updateQuality(ConnectionQuality newQuality) {
    if (_currentQuality != newQuality) {
      _currentQuality = newQuality;
      if (onQualityChanged != null) {
        onQualityChanged!(newQuality);
      }
    }
  }

  /// Get quality as string
  String getQualityString() {
    switch (_currentQuality) {
      case ConnectionQuality.excellent:
        return 'Excellent';
      case ConnectionQuality.good:
        return 'Good';
      case ConnectionQuality.fair:
        return 'Fair';
      case ConnectionQuality.poor:
        return 'Poor';
      case ConnectionQuality.disconnected:
        return 'Disconnected';
    }
  }

  /// Get quality color
  static getQualityColor(ConnectionQuality quality) {
    switch (quality) {
      case ConnectionQuality.excellent:
      case ConnectionQuality.good:
        return const Color(0xFF4CAF50); // Green
      case ConnectionQuality.fair:
        return const Color(0xFFFFC107); // Amber
      case ConnectionQuality.poor:
        return const Color(0xFFFF9800); // Orange
      case ConnectionQuality.disconnected:
        return const Color(0xFFF44336); // Red
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _peerConnection = null;
    _currentQuality = ConnectionQuality.disconnected;
  }
}
