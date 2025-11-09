import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'camera_capture_service.dart';

class SlideCameraController {
  SlideCameraController({CameraCaptureService? captureService})
      : _captureService = captureService ?? CameraCaptureService();

  final CameraCaptureService _captureService;

  CameraController? get previewController => _captureService.controller;
  bool get isInitialized => _captureService.isInitialized;

  Future<void> start(CameraDescription description) async {
    await _captureService.initialize(description);
  }

  Future<void> stop() async {
    await _captureService.dispose();
  }

  Future<Uint8List?> captureFrame() {
    return _captureService.captureFrame();
  }
}


