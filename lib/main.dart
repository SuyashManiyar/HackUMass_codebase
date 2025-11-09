import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'conversation/conversation_controller.dart';
import 'screens/connect_camera_screen.dart';
import 'screens/share_camera_screen.dart';
import 'test_pipeline_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

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
  
  // Signaling server URL - IMPORTANT: Change this based on your setup
  // For Android Emulator: use 'http://10.0.2.2:3000'
  // For Physical Device: use 'http://YOUR_COMPUTER_IP:3000' (e.g., 'http://192.168.1.100:3000')
  // For iOS Simulator: use 'http://localhost:3000'
  static const String _serverUrl = 'http://10.0.0.52:3000';
  
  // TODO: Replace with your Gemini API key
  // Get your API key from: https://makersuite.google.com/app/apikey
  static const String _apiKey = 'AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0';
  
  // TODO: Replace with your local API URL (e.g., 'http://192.168.1.100:8000/api/process-image')
  static const String _apiUrl = 'http://10.0.0.52:8000/api/process-image';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeCameras());
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
      // Stop camera
      _stopConversation();
      await _cameraController?.dispose();
      setState(() {
        _cameraController = null;
        _isCameraActive = false;
      });
    } else {
      // Start camera
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

    // Set up timer to capture frame every 5 seconds
    _frameCaptureTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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
        });
      }
      
      // Send image to API
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
      
      // Add image file to the request
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'frame_${DateTime.now().millisecondsSinceEpoch}.jpg',
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
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

      final imageBytes = await _image!.readAsBytes();
      final prompt = TextPart('Describe this image in detail.');

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)]),
      ]);

      setState(() {
        _description = response.text ?? 'No description available';
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Remote camera options
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
                  label: const Text('Open Local Camera'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),
                if (_image != null)
                  Column(
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
                  )
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
                        icon:
                            Icon(_isConversationActive ? Icons.stop : Icons.chat),
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
