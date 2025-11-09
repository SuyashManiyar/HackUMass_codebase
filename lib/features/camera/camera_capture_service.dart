import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';

class CameraCaptureService {
  CameraController? _controller;

  CameraController? get controller => _controller;

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  Future<void> initialize(
    CameraDescription description, {
    ResolutionPreset preset = ResolutionPreset.high,
    bool enableAudio = false,
  }) async {
    final existing = _controller;
    if (existing != null) {
      await existing.dispose();
    }

    final controller = CameraController(
      description,
      preset,
      enableAudio: enableAudio,
    );
    _controller = controller;
    await controller.initialize();
  }

  Future<Uint8List?> captureFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    final picture = await controller.takePicture();
    final file = File(picture.path);
    try {
      return file.readAsBytes();
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}


