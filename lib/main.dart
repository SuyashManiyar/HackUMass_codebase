import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';

import 'conversation/conversation_controller.dart';
import 'pipeline_service.dart';
import 'screens/connect_camera_screen.dart';
import 'screens/share_camera_screen.dart';
import 'speech_service.dart';
import 'test_pipeline_page.dart';
import 'gemini_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
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
  File? _image;
  final ImagePicker _picker = ImagePicker();
  String? _description;
  bool _isLoading = false;
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isCameraActive = false;
  bool _isConversationActive = false;
  Timer? _frameCaptureTimer;
  Uint8List? _currentFrame;
  Map<String, dynamic>? _apiResponse;
  bool _isSendingToApi = false;
  bool _showCaptured = false;

  final PipelineService _pipelineService = PipelineService(
    speechService: SpeechService(),
  );
  String _recognizedText = '';
  String _reversedText = '';
  bool _isProcessingSpeech = false;

  static const String _serverUrl = 'http://10.0.0.52:3000';
  static const String _apiKey = 'AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0';
  static const String _apiUrl = 'http://10.13.105.159:8000/api/process-image';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeCameras());
    unawaited(_pipelineService.initialize());
  }

  Future<void> _initializeCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
      });
    } catch (e) {
      debugPrint('Error loading cameras: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load cameras: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _captureImage() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile == null) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _image = File(pickedFile.path);
        _description = null;
      });
    } catch (e) {
      debugPrint('Error capturing image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleCamera() async {
    if (_isCameraActive) {
      _stopConversation();
      await _cameraController?.dispose();
      setState(() {
        _cameraController = null;
        _isCameraActive = false;
      });
    } else {
      await ConversationController.active?.interrupt();
      if (_cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cameras available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final camera = _cameras.first;
        await _cameraController?.dispose();
        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraActive = true;
          });
        }
      } catch (e) {
        debugPrint('Error initializing camera: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error starting camera: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _startConversation() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isConversationActive = true;
    });

    _captureFrame();
    _frameCaptureTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _captureFrame();
    });
  }

  void _stopConversation() {
    _frameCaptureTimer?.cancel();
    _frameCaptureTimer = null;
    setState(() {
      _isConversationActive = false;
      _currentFrame = null;
      _apiResponse = null;
    });
  }

  Future<void> _captureFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final image = await _cameraController!.takePicture();
      final imageBytes = await File(image.path).readAsBytes();

      if (mounted) {
        setState(() {
          _currentFrame = imageBytes;
          _showCaptured = true;
        });

        Timer(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _showCaptured = false;
            });
          }
        });
      }

      await _sendImageToApi(imageBytes);
    } catch (e) {
      debugPrint('Error capturing frame: $e');
    }
  }

  Future<void> _sendImageToApi(Uint8List imageBytes) async {
    if (_apiUrl.isEmpty || _apiUrl == 'YOUR_API_URL_HERE') {
      debugPrint('API URL not configured');
      return;
    }

    setState(() {
      _isSendingToApi = true;
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'image_$timestamp.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body) as Map<String, dynamic>;

        if (mounted) {
          setState(() {
            _apiResponse = jsonResponse;
            _isSendingToApi = false;
          });
        }
      } else {
        debugPrint('API request failed with status: ${response.statusCode}');
        if (mounted) {
          setState(() {
            _apiResponse = {
              'error': 'API request failed',
              'status_code': response.statusCode,
              'message': response.body,
            };
            _isSendingToApi = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error sending image to API: $e');
      if (mounted) {
        setState(() {
          _apiResponse = {
            'error': 'Failed to connect to API',
            'message': e.toString(),
          };
          _isSendingToApi = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _stopConversation();
    _cameraController?.dispose();
    _pipelineService.dispose();
    super.dispose();
  }

  Future<void> _describeImage() async {
    if (_image == null) return;

    if (_apiKey.isEmpty || _apiKey == 'YOUR_API_KEY_HERE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set your Gemini API key in the code'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _description = null;
    });

    try {
      final imageBytes = await _image!.readAsBytes();
      final result = await getGeminiResponse(imageBytes);

      setState(() {
        _description = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error describing image: $e');
    }
  }

  void _onSpeechResult(String text, bool isFinal) {
    setState(() {
      _recognizedText = text;
    });
  }

  void _startListening() {
    setState(() {
      _recognizedText = '';
      _reversedText = '';
      _isProcessingSpeech = false;
    });
    _pipelineService.startListening(_onSpeechResult);
  }

  Future<void> _stopListening() async {
    if (_isProcessingSpeech) return;

    setState(() {
      _isProcessingSpeech = true;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final finalText = await _pipelineService.stopListening();

    final textToUse = finalText.isNotEmpty ? finalText : _recognizedText;

    if (textToUse.isNotEmpty) {
      final reversed = _pipelineService.reverseText(textToUse);
      setState(() {
        _recognizedText = textToUse;
        _reversedText = reversed;
      });
      await _pipelineService.speakText(reversed);
    }

    setState(() {
      _isProcessingSpeech = false;
    });
  }

  Widget _buildCameraOverlay() {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: CameraPreview(_cameraController!),
        ),
        if (_currentFrame != null)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 150,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  _currentFrame!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        if (_showCaptured)
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Captured',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        if (_apiResponse != null)
          Positioned(
            bottom: 120,
            left: 16,
            right: 16,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.api, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'API Response:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_isSendingToApi)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      const JsonEncoder.withIndent('  ').convert(_apiResponse),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageReview() {
    if (_image == null) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  _image!,
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _describeImage,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? 'Analyzing...' : 'Describe Image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            if (_description != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Description:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _description!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpeechControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recognized Text: $_recognizedText',
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Reversed Text: $_reversedText',
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            ElevatedButton(
              onPressed: _startListening,
              child: const Text('Start Listening'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _stopListening,
              child: const Text('Stop Listening'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 180),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ShareCameraScreen(
                                  serverUrl: _serverUrl,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.videocam),
                          label: const Text('Share Camera'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ConnectCameraScreen(
                                  serverUrl: _serverUrl,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Connect'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: Text(_isCameraActive ? 'Capture image' : 'Open Local Camera'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                if (_isCameraActive && _cameraController != null)
                  SizedBox(
                    height: 400,
                    child: _buildCameraOverlay(),
                  )
                else if (_image != null)
                  _buildImageReview()
                else
                  Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        'No image captured',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final summaryRaw =
                          await rootBundle.loadString('assets/data/summary.json');
                      final summary =
                          jsonDecode(summaryRaw) as Map<String, dynamic>;
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TestPipelinePage(summary: summary),
                        ),
                      );
                    } catch (err) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Voice test failed: $err')),
                      );
                    }
                  },
                  child: const Text('TEST VOICE PIPELINE PAGE'),
                ),
                const SizedBox(height: 24),
                _buildSpeechControls(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCameraActive)
                      ElevatedButton.icon(
                        onPressed:
                            _isConversationActive ? _stopConversation : _startConversation,
                        icon: Icon(_isConversationActive ? Icons.stop : Icons.chat),
                        label: Text(
                          _isConversationActive
                              ? 'Stop Conversation'
                              : 'Start Conversation',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor:
                              _isConversationActive ? Colors.red : Colors.green,
                        ),
                      ),
                    if (_isCameraActive) const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _toggleCamera,
                      icon: Icon(_isCameraActive
                          ? Icons.camera_alt_outlined
                          : Icons.camera_alt),
                      label: Text(
                        _isCameraActive ? 'Stop Camera' : 'Start Live Camera',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                    if (_currentFrame != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Most Recent Frame Sent',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _currentFrame!,
                                height: 120,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_apiResponse != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'API Response',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              const JsonEncoder.withIndent('  ').convert(_apiResponse),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_isSendingToApi) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
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