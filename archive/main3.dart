import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'gemini_service.dart';
import 'pipeline_service.dart';

void main() {
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

  final PipelineService _pipelineService = PipelineService();
  String _recognizedText = '';
  String _reversedText = '';
  bool _isSpeechInitialized = false;
  bool _isProcessingSpeech = false;

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
          _description = null;
        });
      }
    } catch (e) {
      print('Error capturing image: $e');
    }
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
                    'Speech Recognition',
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
                      child: Column(
                        children: [
                          Text(
                            _recognizedText.isEmpty ? 'Press and hold mic to speak' : _recognizedText,
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          if (_reversedText.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'Reversed:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _reversedText,
                              style: const TextStyle(fontSize: 16, color: Colors.blue),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onLongPressStart: (_) => _startListening(),
                      onLongPressEnd: (_) => _stopListening(),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _pipelineService.isListening
                              ? Colors.red
                              : _isProcessingSpeech
                                  ? Colors.orange
                                  : Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: _isProcessingSpeech
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
                          ? 'Listening...'
                          : _isProcessingSpeech
                              ? 'Processing...'
                              : 'Hold to speak',
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

