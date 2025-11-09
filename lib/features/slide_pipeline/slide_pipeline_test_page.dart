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
  Uint8List? _imageBytesA;
  Uint8List? _imageBytesB;
  bool _isLoading = false;
  String? _error;
  SlideComparisonResult? _comparisonResult;

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  Future<void> _pickImageForSlot({
    required int slotIndex,
    required ImageSource source,
  }) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 95);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        if (slotIndex == 0) {
          _imageBytesA = bytes;
        } else {
          _imageBytesB = bytes;
        }
        _comparisonResult = null;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to pick image: $error';
      });
    }
  }

  Future<void> _pickTwoFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 95);
      if (files.isEmpty) return;

      final selected = files.take(2).toList();
      final bytesList = await Future.wait(
        selected.map((file) => file.readAsBytes()),
      );

      setState(() {
        _imageBytesA = bytesList.isNotEmpty ? bytesList[0] : null;
        _imageBytesB = bytesList.length > 1 ? bytesList[1] : null;
        _comparisonResult = null;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to pick images: $error';
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _imageBytesA = null;
      _imageBytesB = null;
      _comparisonResult = null;
      _error = null;
    });
  }

  Future<void> _runComparison() async {
    final imageA = _imageBytesA;
    final imageB = _imageBytesB;

    if (imageA == null || imageB == null) {
      setState(() {
        _error = 'Select two images before running the comparison.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _comparisonResult = null;
    });

    try {
      final response = await _slideClient.compareSlides(imageA, imageB);
      setState(() {
        _comparisonResult = response;
      });
    } catch (error, stackTrace) {
      debugPrint('Slide comparison failed: $error\n$stackTrace');
      setState(() {
        _error = 'Slide comparison failed: $error';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Slide Pipeline Tester')),
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
                    '1. Capture / Select Slide Frames',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildAcquisitionControls(),
                  const SizedBox(height: 12),
                  _buildSelectedPreviews(),
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
                    '2. Run Slide Comparison',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _runComparison,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Processing…' : 'Compare Slides'),
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
                  if (_comparisonResult != null)
                    _buildResultsContent(_comparisonResult!)
                  else
                    const Text(
                      'Select two slides and tap “Compare Slides” to see results.',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcquisitionControls() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () =>
                    _pickImageForSlot(slotIndex: 0, source: ImageSource.camera),
          icon: const Icon(Icons.photo_camera_front),
          label: const Text('Capture Slide A'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () =>
                    _pickImageForSlot(slotIndex: 1, source: ImageSource.camera),
          icon: const Icon(Icons.photo_camera_back),
          label: const Text('Capture Slide B'),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _pickTwoFromGallery,
          icon: const Icon(Icons.collections),
          label: const Text('Pick Two from Gallery'),
        ),
        TextButton.icon(
          onPressed: _isLoading ? null : _clearSelection,
          icon: const Icon(Icons.clear),
          label: const Text('Clear Selection'),
        ),
      ],
    );
  }

  Widget _buildSelectedPreviews() {
    return Row(
      children: [
        Expanded(child: _buildImagePreview('Slide A', _imageBytesA)),
        const SizedBox(width: 12),
        Expanded(child: _buildImagePreview('Slide B', _imageBytesB)),
      ],
    );
  }

  Widget _buildImagePreview(String label, Uint8List? bytes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SizedBox(
              height: 160,
              child: bytes == null
                  ? const Center(child: Text('No image selected'))
                  : Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsContent(SlideComparisonResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Chip(
              avatar: Icon(
                result.changed ? Icons.warning_amber : Icons.check_circle,
                color: result.changed ? Colors.orange : Colors.green,
              ),
              label: Text(result.changed ? 'Slides differ' : 'Slides match'),
            ),
            Chip(
              avatar: Icon(
                result.areSameSlide ? Icons.copy : Icons.compare_arrows,
                color: result.areSameSlide ? Colors.blue : Colors.redAccent,
              ),
              label: Text(
                result.areSameSlide
                    ? 'SSIM indicates same slide'
                    : 'SSIM indicates change',
              ),
            ),
            Chip(
              label: Text(
                'Sequence similarity: ${(result.sequenceSimilarity * 100).toStringAsFixed(1)}%',
              ),
            ),
            Chip(
              label: Text(
                'Token delta: ${(result.tokenDelta * 100).toStringAsFixed(1)}%',
              ),
            ),
            Chip(
              label: Text('SSIM score: ${result.ssimScore.toStringAsFixed(4)}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSlideDetails('Slide A', result.slide1),
        const SizedBox(height: 24),
        _buildSlideDetails('Slide B', result.slide2),
      ],
    );
  }

  Widget _buildSlideDetails(String label, SlideImageAnalysis analysis) {
    final boundingBoxText = analysis.boundingBox == null
        ? 'No bounding box detected'
        : analysis.boundingBox!
              .map(
                (point) =>
                    '(${point.x.toStringAsFixed(0)}, ${point.y.toStringAsFixed(0)})',
              )
              .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildResultImageCard(
              title: 'Annotated (with bounding box)',
              imageBytes: analysis.annotatedImage,
              placeholder: analysis.slideDetected
                  ? 'Annotated image unavailable'
                  : 'No slide detected',
            ),
            _buildResultImageCard(
              title: 'Cropped Slide',
              imageBytes: analysis.croppedImage,
              placeholder: 'Cropped image unavailable',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Bounding box: $boundingBoxText'),
        const SizedBox(height: 8),
        Text(
          'OCR text (${analysis.ocrWordCount} words, ${analysis.ocrCharCount} chars):',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            analysis.ocrText.isEmpty
                ? 'No OCR text extracted.'
                : analysis.ocrText,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildResultImageCard({
    required String title,
    required Uint8List? imageBytes,
    required String placeholder,
  }) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 140,
                  child: imageBytes == null
                      ? Center(
                          child: Text(placeholder, textAlign: TextAlign.center),
                        )
                      : Image.memory(imageBytes, fit: BoxFit.cover),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
