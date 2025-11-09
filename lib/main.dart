import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Error initializing cameras: $e');
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
  File? _image;
  final ImagePicker _picker = ImagePicker();
  String? _description;
  bool _isLoading = false;
  CameraController? _cameraController;
  bool _isCameraActive = false;
  bool _isConversationActive = false;
  Timer? _frameCaptureTimer;
  Uint8List? _currentFrame;
  Uint8List? _previousFrame;
  Map<String, dynamic>? _apiResponse;
  bool _isSendingToApi = false;
  bool _showCaptured = false;
  
  // TODO: Replace with your Gemini API key
  // Get your API key from: https://makersuite.google.com/app/apikey
  static const String _apiKey = 'AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0';
  
  // TODO: Replace with your local API URL (e.g., 'http://192.168.1.100:8000/api/process-image')
  static const String _apiUrl = 'http://10.13.105.159:8000/api/process-image';

  Future<void> _toggleCamera() async {
    if (_isCameraActive) {
      // Stop camera
      _stopConversation();
      await _cameraController?.dispose();
      setState(() {
        _cameraController = null;
        _isCameraActive = false;
      });
    } else {
      // Start camera
      if (cameras == null || cameras!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cameras available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        final camera = cameras!.first;
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
        print('Error initializing camera: $e');
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

    // Capture initial frame
    _captureFrame();

    // Set up timer to capture frame every 10 seconds
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
      _previousFrame = null;
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
          // Store current frame as previous before updating
          _previousFrame = _currentFrame;
          _currentFrame = imageBytes;
          // Show "captured" message
          _showCaptured = true;
        });
        
        // Hide "captured" message after 1 second
        Timer(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _showCaptured = false;
            });
          }
        });
      }
      
      // Send current frame to API
      await _sendImageToApi(imageBytes);
    } catch (e) {
      print('Error capturing frame: $e');
    }
  }
  
  Future<void> _sendImageToApi(Uint8List imageBytes) async {
    if (_apiUrl.isEmpty || _apiUrl == 'YOUR_API_URL_HERE') {
      print('API URL not configured');
      return;
    }

    setState(() {
      _isSendingToApi = true;
    });

    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // Add image
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'image_$timestamp.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        // Parse JSON response
        final jsonResponse = json.decode(response.body) as Map<String, dynamic>;
        
        if (mounted) {
          setState(() {
            _apiResponse = jsonResponse;
            _isSendingToApi = false;
          });
        }
      } else {
        print('API request failed with status: ${response.statusCode}');
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
      print('Error sending image to API: $e');
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
    super.dispose();
  }

  Future<void> _describeImage() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _description = null;
    });

    try {
      final imageBytes = await _image!.readAsBytes();
      final result = await get_gemini_response(imageBytes);

      setState(() {
        _description = result.toString();
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
      print('Error describing image: $e');
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

  @override
  void dispose() {
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
      body: Stack(
        children: [
          // Camera preview or image display
          if (_isCameraActive && _cameraController != null)
            Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: CameraPreview(_cameraController!),
                ),
                // Display current frame overlay
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
                // Display "Captured" message overlay
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
                // Display API response overlay
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
                              JsonEncoder.withIndent('  ').convert(_apiResponse),
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
            )
          else if (_image != null)
            SingleChildScrollView(
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
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
            )
          else
            Center(
              child: Container(
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
            ),
          
          // Buttons at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Start Conversation button (only when camera is active)
                    if (_isCameraActive)
                      ElevatedButton.icon(
                        onPressed: _isConversationActive ? _stopConversation : _startConversation,
                        icon: Icon(_isConversationActive ? Icons.stop : Icons.chat),
                        label: Text(_isConversationActive ? 'Stop Conversation' : 'Start Conversation'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: _isConversationActive ? Colors.red : Colors.green,
                        ),
                      ),
                    if (_isCameraActive) const SizedBox(height: 12),
                    // Toggle Camera button
                    ElevatedButton.icon(
                      onPressed: _toggleCamera,
                      icon: Icon(_isCameraActive ? Icons.camera_alt_outlined : Icons.camera_alt),
                      label: Text(_isCameraActive ? 'Stop Camera' : 'Start Live Camera'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        minimumSize: const Size(double.infinity, 50),
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