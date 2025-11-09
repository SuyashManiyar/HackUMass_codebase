import 'package:camera/camera.dart';

class CameraPreviewService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;

  Future<void> initialize() async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) return;

    _controller = CameraController(
      _cameras![0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _controller!.initialize();
    _isInitialized = true;
  }

  Future<String?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return null;

    try {
      final image = await _controller!.takePicture();
      return image.path;
    } catch (e) {
      print('Error taking picture: $e');
      return null;
    }
  }

  void dispose() {
    _controller?.dispose();
  }
}