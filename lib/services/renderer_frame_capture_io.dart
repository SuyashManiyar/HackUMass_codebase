import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<Uint8List> captureRendererFrame(RTCVideoRenderer renderer) async {
  final imageData = await renderer.captureFrame();
  if (imageData == null) {
    throw Exception('Failed to capture frame');
  }
  return imageData;
}

