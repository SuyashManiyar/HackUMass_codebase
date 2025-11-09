import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<Uint8List> captureRendererFrame(RTCVideoRenderer renderer) {
  throw UnsupportedError('Frame capture is not supported on this platform');
}

