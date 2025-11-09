import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/fastapi_client.dart';
import 'slide_client.dart';

class SlidePipelineTestPage extends StatefulWidget {
  const SlidePipelineTestPage({super.key});

  @override
  State<SlidePipelineTestPage> createState() => _SlidePipelineTestPageState();
}

class _SlidePipelineTestPageState extends State<SlidePipelineTestPage> {
  final ImagePicker _picker = ImagePicker();
  final FastApiClient _apiClient = FastApiClient();

  late final SlideClient _slideClient = SlideClient(apiClient: _apiClient);

  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _error;
  SlideProcessResult? _result;

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _result = null;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to pick image: $error';
      });
    }
  }

  Future<void> _runPipeline() async {
    final bytes = _imageBytes;
    if (bytes == null) {
      setState(() {
        _error = 'Select an image first.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final response = await _slideClient.processSlide(bytes);
      setState(() {
        _result = response;
      });
    } catch (error, stackTrace) {
      debugPrint('Slide pipeline test failed: $error\n$stackTrace');
      setState(() {
        _error = 'Pipeline test failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryJson = _result?.summary == null
        ? '—'
        : const JsonEncoder.withIndent('  ').convert(_result!.summary);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Slide Pipeline Tester'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '1. Capture / Select Slide Frame',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Use Camera'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.collections),
                        label: const Text('Pick from Gallery'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_imageBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade200,
                      ),
                      child: const Center(
                        child: Text('No image selected'),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '2. Run Slide Pipeline',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runPipeline,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Processing…' : 'Analyze Slide'),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '3. Results',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_result != null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Chip(
                          label: Text(
                            _result!.slideDetected ? 'Slide Detected' : 'Slide Not Detected',
                          ),
                          avatar: Icon(
                            _result!.slideDetected ? Icons.check_circle : Icons.error_outline,
                            color: _result!.slideDetected ? Colors.green : Colors.orange,
                          ),
                        ),
                        Chip(
                          label: Text(
                            _result!.changed ? 'New Slide' : 'No Change',
                          ),
                          avatar: Icon(
                            _result!.changed ? Icons.fiber_new : Icons.repeat,
                            color: _result!.changed ? Colors.blue : Colors.grey,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text('Run the pipeline to see results.'),
                  const SizedBox(height: 16),
                  Text(
                    'Summary JSON',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      summaryJson,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


