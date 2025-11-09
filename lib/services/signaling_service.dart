import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// TODO: Replace prints with a logger
class SignalingService {
  io.Socket? _socket;
  String? _pairingCode;
  bool _isConnected = false;

  // Callbacks
  Function(RTCSessionDescription)? _onOfferCallback;
  Function(RTCSessionDescription)? _onAnswerCallback;
  Function(RTCIceCandidate)? _onIceCandidateCallback;
  Function()? _onReceiverJoinedCallback;
  Function()? _onPeerDisconnectedCallback;

  bool get isConnected => _isConnected;
  String? get pairingCode => _pairingCode;

  /// Connect to the signaling server
  Future<void> connect(String serverUrl) async {
    if (_isConnected) {
      return;
    }

    final completer = Completer<void>();

    try {
      _socket = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

      _socket!.onConnect((_) {
        _isConnected = true;
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
      });

      _socket!.onConnectError((error) {
        _isConnected = false;
        if (!completer.isCompleted) {
          completer.completeError(Exception('Connection error: $error'));
        }
      });

      // Listen for offer
      _socket!.on('offer', (data) {
        if (_onOfferCallback != null && data['offer'] != null) {
          final offer = RTCSessionDescription(
            data['offer']['sdp'],
            data['offer']['type'],
          );
          _onOfferCallback!(offer);
        }
      });

      // Listen for answer
      _socket!.on('answer', (data) {
        if (_onAnswerCallback != null && data['answer'] != null) {
          final answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          _onAnswerCallback!(answer);
        }
      });

      // Listen for ICE candidates
      _socket!.on('ice-candidate', (data) {
        if (_onIceCandidateCallback != null && data['candidate'] != null) {
          final candidate = RTCIceCandidate(
            data['candidate']['candidate'],
            data['candidate']['sdpMid'],
            data['candidate']['sdpMLineIndex'],
          );
          _onIceCandidateCallback!(candidate);
        }
      });

      // Listen for receiver joined
      _socket!.on('receiver-joined', (_) {
        if (_onReceiverJoinedCallback != null) {
          _onReceiverJoinedCallback!();
        }
      });

      // Listen for peer disconnected
      _socket!.on('peer-disconnected', (_) {
        if (_onPeerDisconnectedCallback != null) {
          _onPeerDisconnectedCallback!();
        }
      });

      _socket!.connect();

      // Wait for the connection to complete or fail
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _isConnected = false;
      throw Exception('Connection to signaling server timed out');
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  /// Register as sender and get pairing code
  Future<String> registerAsSender() async {
    if (!_isConnected || _socket == null) {
      throw Exception('Not connected to signaling server');
    }

    try {
      final completer = Completer<Map<String, dynamic>>();

      _socket!.emitWithAck('register-sender', null, ack: (data) {
        completer.complete(Map<String, dynamic>.from(data));
      });

      final response = await completer.future.timeout(const Duration(seconds: 5));

      if (response['success'] == true && response['pairingCode'] != null) {
        _pairingCode = response['pairingCode'];
        return _pairingCode!;
      } else {
        throw Exception(response['error'] ?? 'Failed to register as sender');
      }
    } on TimeoutException {
      throw Exception('Registering as sender timed out');
    } catch (e) {
      rethrow;
    }
  }

  /// Join as receiver with pairing code
  Future<void> joinAsReceiver(String pairingCode) async {
    if (!_isConnected || _socket == null) {
      throw Exception('Not connected to signaling server');
    }

    try {
      final completer = Completer<Map<String, dynamic>>();

      _socket!.emitWithAck('join-receiver', {'pairingCode': pairingCode}, ack: (data) {
        completer.complete(Map<String, dynamic>.from(data));
      });

      final response = await completer.future.timeout(const Duration(seconds: 5));

      if (response['success'] == true) {
        _pairingCode = pairingCode;
      } else {
        throw Exception(response['error'] ?? 'Failed to join as receiver');
      }
    } on TimeoutException {
      throw Exception('Joining as receiver timed out');
    } catch (e) {
      rethrow;
    }
  }

  /// Send WebRTC offer
  Future<void> sendOffer(RTCSessionDescription offer) async {
    if (!_isConnected || _socket == null || _pairingCode == null) {
      throw Exception('Not ready to send offer');
    }

    try {
      _socket!.emit('offer', {
        'pairingCode': _pairingCode,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Send WebRTC answer
  Future<void> sendAnswer(RTCSessionDescription answer) async {
    if (!_isConnected || _socket == null || _pairingCode == null) {
      throw Exception('Not ready to send answer');
    }

    try {
      _socket!.emit('answer', {
        'pairingCode': _pairingCode,
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        },
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Send ICE candidate
  Future<void> sendIceCandidate(RTCIceCandidate candidate, bool isSender) async {
    if (!_isConnected || _socket == null || _pairingCode == null) {
      throw Exception('Not ready to send ICE candidate');
    }

    try {
      _socket!.emit('ice-candidate', {
        'pairingCode': _pairingCode,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        'isSender': isSender,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Set callback for receiving offers
  void onOffer(Function(RTCSessionDescription) callback) {
    _onOfferCallback = callback;
  }

  /// Set callback for receiving answers
  void onAnswer(Function(RTCSessionDescription) callback) {
    _onAnswerCallback = callback;
  }

  /// Set callback for receiving ICE candidates
  void onIceCandidate(Function(RTCIceCandidate) callback) {
    _onIceCandidateCallback = callback;
  }

  /// Set callback for receiver joined event
  void onReceiverJoined(Function() callback) {
    _onReceiverJoinedCallback = callback;
  }

  /// Set callback for peer disconnected event
  void onPeerDisconnected(Function() callback) {
    _onPeerDisconnectedCallback = callback;
  }

  /// Disconnect and cleanup
  Future<void> disconnect() async {
    try {
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _isConnected = false;
      _pairingCode = null;

      // Clear callbacks
      _onOfferCallback = null;
      _onAnswerCallback = null;
      _onIceCandidateCallback = null;
      _onReceiverJoinedCallback = null;
      _onPeerDisconnectedCallback = null;
    } catch (e) {
      // handle error
    }
  }
}
