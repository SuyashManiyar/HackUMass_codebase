import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<Uint8List> captureRendererFrame(RTCVideoRenderer renderer) async {
  final stream = renderer.srcObject;
  if (stream == null) {
    throw Exception('Renderer has no attached stream');
  }

  final videoTracks = stream.getVideoTracks();
  if (videoTracks.isEmpty) {
    throw Exception('No video tracks available for capture');
  }

  final frameBuffer = await videoTracks.first.captureFrame();
  return frameBuffer.asUint8List();
}

