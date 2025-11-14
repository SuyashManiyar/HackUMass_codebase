import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'gemini_service.dart';
import 'pipeline_service.dart';
import 'camera_preview_service.dart';
import 'end_summary_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SightScribe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(title: 'SightScribe'),
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
  bool _isCapturing = false;
  final CameraPreviewService _cameraService = CameraPreviewService();
  final PipelineService _pipelineService = PipelineService();

  Map<String, dynamic>? _currentSlideSummary;
  List<Map<String, dynamic>> _allSlideSummaries = [];

  String _transcription = '';
  bool _isSpeechInitialized = false;
  bool _isProcessingPipeline = false;
  bool _isAnalyzingSlide = false;

  Timer? _captureTimer;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _pipelineService.initialize();
    setState(() {
      _isSpeechInitialized = _pipelineService.isInitialized;
    });
  }

  Future<void> _toggleCapturing() async {
    if (_isCapturing) {
      _stopCapturing();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EndSummaryPage(slideSummaries: _allSlideSummaries),
        ),
      );
    } else {
      await _startCapturing();
    }
  }

  Future<void> _startCapturing() async {
    await _cameraService.initialize();

    setState(() {
      _isCapturing = true;
      _allSlideSummaries = [];
      _currentSlideSummary = null;
    });

    await _captureAndAnalyze();

    _captureTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _captureAndAnalyze();
    });
  }

  void _stopCapturing() {
    _captureTimer?.cancel();
    _cameraService.dispose();

    setState(() {
      _isCapturing = false;
    });
  }

  Future<void> _captureAndAnalyze() async {
    setState(() {
      _isAnalyzingSlide = true;
    });

    final imagePath = await _cameraService.takePicture();

    if (imagePath != null) {
      try {
        final imageBytes = await File(imagePath).readAsBytes();
        final result = await get_gemini_response(imageBytes);

        setState(() {
          _currentSlideSummary = result;
          _allSlideSummaries.add(result);
          _isAnalyzingSlide = false;
        });
      } catch (e) {
        print('Error analyzing slide: $e');
        setState(() {
          _isAnalyzingSlide = false;
        });
      }
    }
  }

  void _onTranscriptionUpdate(String text) {
    setState(() {
      _transcription = text;
    });
  }

  Future<void> _toggleMicrophone() async {
    if (_currentSlideSummary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a slide first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_pipelineService.isListening) {
      setState(() {
        _isProcessingPipeline = true;
      });

      await _pipelineService.stopPipelineAndProcess(_currentSlideSummary.toString());

      setState(() {
        _isProcessingPipeline = false;
      });
    } else {
      setState(() {
        _transcription = '';
      });
      await _pipelineService.startPipeline(_currentSlideSummary.toString(), _onTranscriptionUpdate);
      setState(() {});
    }
  }

  String _getDisplaySummary() {
    if (_currentSlideSummary == null) return 'No summary available';

    final displaySummary = _currentSlideSummary!['display_summary'];
    if (displaySummary != null && displaySummary is List && displaySummary.isNotEmpty) {
      return displaySummary[0].toString();
    }

    return 'No summary available';
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _cameraService.dispose();
    _pipelineService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: InkWell(
              onTap: _toggleCapturing,
              child: Container(
                width: double.infinity,
                color: _isCapturing ? Colors.red : Colors.green,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _isCapturing ? 'Stop Capturing' : 'Start Capturing',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _isCapturing && _cameraService.isInitialized
                  ? Center(
                child: _cameraService.controller!.value.aspectRatio > 1
                    ? AspectRatio(
                  aspectRatio: _cameraService.controller!.value.aspectRatio,
                  child: CameraPreview(_cameraService.controller!),
                )
                    : FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _cameraService.controller!.value.previewSize!.height,
                    height: _cameraService.controller!.value.previewSize!.width,
                    child: CameraPreview(_cameraService.controller!),
                  ),
                ),
              )
                  : const Center(
                child: Text(
                  'Camera Preview',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey[200],
              child: _isAnalyzingSlide
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Slide Captured. Analyzing...',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              )
                  : _currentSlideSummary != null
                  ? SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Slide Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getDisplaySummary(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              )
                  : const Center(
                child: Text(
                  'Slide Summary',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!, width: 2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        _transcription.isEmpty
                            ? (_currentSlideSummary == null
                            ? 'Capture a slide first'
                            : 'Tap mic to ask a question')
                            : _transcription,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _isSpeechInitialized ? _toggleMicrophone : null,
                      child: Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: _pipelineService.isListening
                              ? Colors.red
                              : _isProcessingPipeline
                              ? Colors.orange
                              : (_currentSlideSummary == null ? Colors.grey : Colors.blue),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: _isProcessingPipeline
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _pipelineService.isListening ? Icons.mic : Icons.mic_none,
                              color: Colors.white,
                              size: 30,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _pipelineService.isListening
                                  ? 'Listening... (Tap to stop)'
                                  : _isProcessingPipeline
                                  ? 'Processing...'
                                  : 'Tap to speak',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}