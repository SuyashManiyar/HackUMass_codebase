import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/app_state.dart';
import 'features/camera/camera_controller.dart';
import 'features/camera/camera_capture_service.dart';
import 'features/slide_pipeline/slide_client.dart';
import 'features/slide_pipeline/slide_repo.dart';
import 'features/slide_pipeline/slide_scheduler.dart';
import 'features/voice_pipeline/conversation_controller.dart';
import 'screens/end_summary_page.dart';
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
  late final SlideCameraController _slideCamera;
  late final SlideScheduler _slideScheduler;

  ConversationController? _conversationController;
  StreamSubscription<bool>? _speakingSubscription;

  List<CameraDescription> _availableCameras = [];
  bool _initializingCameras = true;
  bool _initializingCameraController = false;
  bool _cameraReady = false;
  bool _processingSlide = false;
  String? _errorMessage;

  bool _voiceRecording = false;
  bool _voiceProcessing = false;
  bool _voiceSpeaking = false;
  String _voiceTranscript = '';
  String _voiceAnswer = '';
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    _fastApiClient = FastApiClient();
    _slideClient = SlideClient(apiClient: _fastApiClient);
    _cameraCapture = CameraCaptureService();
    _slideCamera = SlideCameraController(captureService: _cameraCapture);
    _slideScheduler = SlideScheduler(
      camera: _cameraCapture,
      client: _slideClient,
      repository: _slideRepository,
      appState: _appState,
    );
    _appState.addListener(_handleAppStateUpdate);

    try {
      _conversationController =
          ConversationController(repository: _slideRepository);
      _speakingSubscription =
          _conversationController!.speakingStream.listen((speaking) {
        if (!mounted) return;
        setState(() {
          _voiceSpeaking = speaking;
        });
      });
    } catch (error) {
      debugPrint('Voice pipeline unavailable: $error');
      _voiceError = 'Voice pipeline unavailable: $error';
    }

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
      _slideScheduler.start();
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

  Future<void> _stopCamera() async {
    if (!_cameraReady || _initializingCameraController) return;
    setState(() {
      _initializingCameraController = true;
    });

    try {
      _slideScheduler.stop();
      await _slideCamera.stop();
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to stop camera: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _initializingCameraController = false;
        });
      }
    }
  }

  Future<void> _toggleVoice() async {
    final controller = _conversationController;
    if (controller == null) {
      setState(() {
        _voiceError ??= 'Voice assistant is unavailable.';
      });
      return;
    }

    if (!_slideRepository.hasSummary) {
      setState(() {
        _voiceError = 'Capture a slide before asking a question.';
      });
      return;
    }

    if (_voiceProcessing) {
      return;
    }

    if (_voiceRecording) {
      setState(() {
        _voiceRecording = false;
        _voiceProcessing = true;
      });
      try {
        final result = await controller.stop();
        if (!mounted) {
          return;
        }
        setState(() {
          _voiceProcessing = false;
          if (result != null) {
            _voiceTranscript = result.transcript;
            _voiceAnswer = result.answer;
            _voiceError = null;
          }
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _voiceProcessing = false;
          _voiceError = error.toString();
        });
      }
    } else {
      try {
        await controller.start();
        if (!mounted) return;
        setState(() {
          _voiceRecording = true;
          _voiceTranscript = '';
          _voiceAnswer = '';
          _voiceError = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _voiceRecording = false;
          _voiceError = error.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _speakingSubscription?.cancel();
    _conversationController?.dispose();
    _appState.removeListener(_handleAppStateUpdate);
    _slideScheduler.stop();
    _cameraCapture.dispose();
    _fastApiClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _appState.latestSummary;
    final slideNumber = _appState.latestSlideNumber;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: _initializingCameras
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCaptureControlRow(context),
                      _buildCameraRow(),
                      _buildSummaryRow(context, slideNumber, summary),
                      _buildVoiceRow(context),
                    ],
                  ),
                  if (_errorMessage != null)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Material(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleCaptureTap(BuildContext context) async {
    if (_cameraReady) {
      await _stopCamera();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EndSummaryPage(
            summaries: _slideRepository.history.toList(),
          ),
        ),
      );
    } else {
      await _initializeCamera();
    }
  }

  Widget _buildCaptureControlRow(BuildContext context) {
    final bool isCapturing = _cameraReady;
    final bool isBusy = _initializingCameraController;
    final Color baseColor = isCapturing ? Colors.red : Colors.green;
    final IconData icon = isBusy
        ? Icons.hourglass_top
        : (isCapturing ? Icons.stop : Icons.camera_alt);
    final String label = isBusy
        ? 'Initializing…'
        : (isCapturing ? 'Stop Capturing' : 'Start Capturing');

    return SizedBox(
      height: 96,
      child: Material(
        color: baseColor,
        child: InkWell(
          onTap: isBusy ? null : () => _handleCaptureTap(context),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 30),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraRow() {
    return Expanded(
      flex: 5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double side =
              constraints.biggest.shortestSide == double.infinity
                  ? constraints.maxWidth
                  : constraints.biggest.shortestSide;
          final controller = _slideCamera.previewController;
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.black),
                child: _cameraReady && controller != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: controller.value.previewSize?.width ?? side,
                            height:
                                controller.value.previewSize?.height ?? side,
                            child: CameraPreview(controller),
                          ),
                        ),
                      )
                    : const Center(
                        child: Text(
                          'Camera Preview',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    int? slideNumber,
    Map<String, dynamic>? summary,
  ) {
    final theme = Theme.of(context);
    final bool processing = _processingSlide;
    final String heading =
        processing ? 'Slide Captured. Analyzing…' : 'Slide Summary';

    String? summaryText;
    if (!processing && summary != null) {
      summaryText = const JsonEncoder.withIndent('  ').convert(summary);
    }

    return Expanded(
      flex: 3,
      child: Container(
        width: double.infinity,
        color: Colors.grey.shade200,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: theme.textTheme.titleMedium,
            ),
            if (!processing && slideNumber != null) ...[
              const SizedBox(height: 4),
              Text(
                'Slide #$slideNumber',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.all(12),
                child: processing
                    ? const Center(child: Text('Please wait…'))
                    : (summaryText != null
                        ? Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              child: SelectableText(
                                summaryText,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                        : const Center(
                            child: Text('Capture a slide first.'),
                          )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRow(BuildContext context) {
    final theme = Theme.of(context);
    final bool voiceReady = _conversationController != null;
    final bool hasSummary = _slideRepository.hasSummary;
    final bool buttonEnabled = voiceReady && hasSummary && !_voiceProcessing;

    String statusText;
    if (!hasSummary) {
      statusText = 'Capture a slide before asking a question.';
    } else if (_voiceError != null) {
      statusText = _voiceError!;
    } else if (_voiceProcessing) {
      statusText = 'Processing response…';
    } else if (_voiceRecording) {
      statusText = 'Listening… tap the button to stop.';
    } else if (_voiceSpeaking) {
      statusText = 'Speaking response…';
    } else if (_voiceAnswer.isNotEmpty) {
      statusText = 'Tap the button to ask another question.';
    } else if (!voiceReady) {
      statusText = 'Voice assistant not initialized.';
    } else {
      statusText = 'Ask about the current slide.';
    }

    return Expanded(
      flex: 3,
      child: Container(
        width: double.infinity,
        color: Colors.grey.shade100,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ask About This Slide',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _voiceError != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _buildTranscriptBox(theme),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: buttonEnabled ? _toggleVoice : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonEnabled
                      ? (_voiceRecording
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary)
                      : null,
                  foregroundColor:
                      buttonEnabled ? Colors.white : theme.colorScheme.onSurface,
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: Icon(_voiceRecording ? Icons.stop : Icons.mic, size: 26),
                label: Text(_voiceRecording ? 'Stop Listening' : 'Tap to Speak'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_voiceAnswer.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Assistant', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(_voiceAnswer),
                    ],
                    if (_voiceError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _voiceError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptBox(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        _voiceTranscript,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      ),
    );
  }
}
