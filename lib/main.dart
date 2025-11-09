import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'gemini_service.dart';
import 'pipeline_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


Future<void> main() async{
  await dotenv.load(fileName: ".env");
  print('Dotenv loaded successfully');
  print('GEMINI_API_KEY exists: ${dotenv.env['GEMINI_API_KEY'] != null}');
  print('OPENROUTER_API_KEY exists: ${dotenv.env['OPNRTR_API_KEY'] != null}');
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
  String? _imageSummary;
  bool _isLoadingImage = false;

  final PipelineService _pipelineService = PipelineService();
  String _transcription = '';
  bool _isSpeechInitialized = false;
  bool _isProcessingPipeline = false;

  @override
  void initState() {
    super.initState();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    await _pipelineService.initialize();
    setState(() {
      _isSpeechInitialized = _pipelineService.isInitialized;
    });
    if (!_isSpeechInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _captureImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _image = File(image.path);
          _imageSummary = null;
        });
      }
    } catch (e) {
      print('Error capturing image: $e');
    }
  }

  Future<void> _describeImage() async {
    if (_image == null) return;

    setState(() {
      _isLoadingImage = true;
      _imageSummary = null;
    });

    try {
      final imageBytes = await _image!.readAsBytes();
      final result = await get_gemini_response(imageBytes);

      setState(() {
        _imageSummary = result.toString();
        _isLoadingImage = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingImage = false;
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

  void _onTranscriptionUpdate(String text) {
    setState(() {
      _transcription = text;
    });
  }

  Future<void> _toggleMicrophone() async {
    if (_imageSummary == null || _imageSummary!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture and analyze an image first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_pipelineService.isListening) {
      setState(() {
        _isProcessingPipeline = true;
      });

      await _pipelineService.stopPipelineAndProcess(_imageSummary!);

      setState(() {
        _isProcessingPipeline = false;
      });
    } else {
      setState(() {
        _transcription = '';
      });
      await _pipelineService.startPipeline(_imageSummary!, _onTranscriptionUpdate);
      setState(() {});
    }
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: <Widget>[
                    ElevatedButton.icon(
                      onPressed: _captureImage,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Open Camera'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                            onPressed: _isLoadingImage ? null : _describeImage,
                            icon: _isLoadingImage
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Icon(Icons.auto_awesome),
                            label: Text(_isLoadingImage ? 'Analyzing...' : 'Describe Image'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                          if (_imageSummary != null) ...[
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
                                    'Image Summary:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _imageSummary!,
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
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!, width: 2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Ask a Question',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (!_isSpeechInitialized)
                    const CircularProgressIndicator()
                  else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Text(
                        _transcription.isEmpty
                            ? (_imageSummary == null
                            ? 'Capture and analyze an image first'
                            : 'Click mic to ask a question')
                            : _transcription,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _toggleMicrophone,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _pipelineService.isListening
                              ? Colors.red
                              : _isProcessingPipeline
                              ? Colors.orange
                              : (_imageSummary == null ? Colors.grey : Colors.blue),
                          shape: BoxShape.circle,
                        ),
                        child: _isProcessingPipeline
                            ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                            : Icon(
                          _pipelineService.isListening ? Icons.mic : Icons.mic_none,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _pipelineService.isListening
                          ? 'Listening... (Click to stop)'
                          : _isProcessingPipeline
                          ? 'Processing...'
                          : 'Click to speak',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}