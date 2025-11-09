import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/app_state.dart';
import 'core/env.dart';
import 'features/camera/camera_controller.dart';
import 'features/camera/camera_capture_service.dart';
import 'features/screens/connect_camera_screen.dart';
import 'features/screens/share_camera_screen.dart';
import 'features/screens/test_pipeline_page.dart';
import 'features/slide_pipeline/slide_client.dart';
import 'features/slide_pipeline/slide_repo.dart';
import 'features/slide_pipeline/slide_scheduler.dart';
import 'features/slide_pipeline/slide_pipeline_test_page.dart';
import 'services/fastapi_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (error) {
    debugPrint('Warning: Could not load .env file: $error');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HackUMass',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(title: 'HackUMass'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AppState _appState = AppState();
  final SlideRepository _slideRepository = SlideRepository();

  late final FastApiClient _fastApiClient;
  late final SlideClient _slideClient;
  late final CameraCaptureService _cameraCapture;
  late final SlideScheduler _slideScheduler;
  late final SlideCameraController _slideCamera;

  List<CameraDescription> _availableCameras = [];
  bool _initializingCameras = true;
  bool _initializingCameraController = false;
  bool _cameraReady = false;
  bool _schedulerActive = false;
  bool _processingSlide = false;
  Uint8List? _lastCapturedFrame;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fastApiClient = FastApiClient();
    _slideClient = SlideClient(apiClient: _fastApiClient);
    _cameraCapture = CameraCaptureService();
    _slideScheduler = SlideScheduler(
      camera: _cameraCapture,
      client: _slideClient,
      repository: _slideRepository,
      appState: _appState,
    );
    _slideCamera = SlideCameraController(captureService: _cameraCapture);
    _appState.addListener(_handleAppStateUpdate);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      setState(() {
        _availableCameras = cameras;
        _initializingCameras = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializingCameras = false;
        _errorMessage = 'Failed to load cameras: $error';
      });
    }
  }

  void _handleAppStateUpdate() {
    if (!mounted) return;
    setState(() {
      _processingSlide = _appState.isProcessingSlide;
    });
  }

  Future<void> _initializeCamera() async {
    if (_cameraReady || _initializingCameraController) return;
    if (_availableCameras.isEmpty) {
      setState(() {
        _errorMessage = 'No cameras available on this device.';
      });
      return;
    }

    setState(() {
      _initializingCameraController = true;
      _errorMessage = null;
    });
    try {
      await _slideCamera.start(_availableCameras.first);
      if (!mounted) return;
      setState(() {
        _cameraReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to initialize camera: $error';
        _cameraReady = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _initializingCameraController = false;
        });
      }
    }
  }

  Future<void> _startScheduler() async {
    await _initializeCamera();
    if (!_cameraReady) return;

    _slideScheduler.start();
    setState(() {
      _schedulerActive = true;
    });
  }

  void _stopScheduler() {
    _slideScheduler.stop();
    setState(() {
      _schedulerActive = false;
    });
  }

  Future<void> _captureOnce() async {
    await _initializeCamera();
    if (!_cameraReady) return;

    final frame = await _cameraCapture.captureFrame();
    if (frame == null) {
      setState(() {
        _errorMessage = 'Failed to capture a frame from the camera.';
      });
      return;
    }

    setState(() {
      _lastCapturedFrame = frame;
      _errorMessage = null;
    });

    _appState.setProcessing(true);
    try {
      final result = await _slideClient.processSlide(frame);
      _applySlideResult(result);
    } catch (error) {
      setState(() {
        _errorMessage = 'Slide processing failed: $error';
      });
    } finally {
      _appState.setProcessing(false);
    }
  }

  void _applySlideResult(SlideProcessResult result) {
    final summary = result.summary;
    if (summary != null) {
      if (result.newSlide || !_slideRepository.hasSummary) {
        _slideRepository.save(summary: summary);
      }
      final latest = _slideRepository.latestSummary ?? summary;
      _appState.updateSlide(summary: latest);
    }
  }

  void _openTestPipeline() {
    final summary = _appState.latestSummary;
    if (summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capture a slide before testing the voice pipeline.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TestPipelinePage(summary: summary),
      ),
    );
  }

  void _openSlidePipelineTester() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SlidePipelineTestPage()),
    );
  }

  @override
  void dispose() {
    _stopScheduler();
    _appState.removeListener(_handleAppStateUpdate);
    _cameraCapture.dispose();
    _fastApiClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _appState.latestSummary;
    final jsonSummary = summary == null
        ? 'No slide processed yet.'
        : const JsonEncoder.withIndent('  ').convert(summary);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'share') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        ShareCameraScreen(serverUrl: Env.signalingServerUrl),
                  ),
                );
              } else if (value == 'connect') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        ConnectCameraScreen(serverUrl: Env.signalingServerUrl),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: Text('Share Camera')),
              PopupMenuItem(
                value: 'connect',
                child: Text('Connect to Remote Camera'),
              ),
            ],
          ),
        ],
      ),
      body: _initializingCameras
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_errorMessage != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _cameraReady ? 'Camera Ready' : 'Camera Idle',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _availableCameras.isEmpty
                                      ? 'No cameras detected'
                                      : 'Available cameras: ${_availableCameras.length}',
                                ),
                              ],
                            ),
                          ),
                          if (_initializingCameraController)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _initializingCameraController
                                ? null
                                : _initializeCamera,
                            child: const Text('Initialize Camera'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_cameraReady && _slideCamera.previewController != null)
                    AspectRatio(
                      aspectRatio:
                          _slideCamera.previewController!.value.aspectRatio,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CameraPreview(_slideCamera.previewController!),
                      ),
                    ),
                  if (_lastCapturedFrame != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Last Captured Frame',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_lastCapturedFrame!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Slide Capture Scheduler',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _schedulerActive
                                          ? 'Running every ${Env.slideCaptureInterval.inSeconds}s'
                                          : 'Scheduler is stopped',
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _schedulerActive,
                                onChanged: (value) {
                                  if (value) {
                                    unawaited(_startScheduler());
                                  } else {
                                    _stopScheduler();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _processingSlide ? null : _captureOnce,
                            icon: _processingSlide
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera),
                            label: Text(
                              _processingSlide ? 'Processing…' : 'Capture Once',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latest Slide Summary',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              jsonSummary,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: summary == null
                                ? null
                                : _openTestPipeline,
                            child: const Text('Test Voice Pipeline'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _openSlidePipelineTester,
                            child: const Text('Open Slide Pipeline Tester'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
