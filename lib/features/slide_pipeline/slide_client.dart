import 'dart:convert';
import 'dart:typed_data';

import '../../services/fastapi_client.dart';

class SlidePoint {
  const SlidePoint({required this.x, required this.y});

  final double x;
  final double y;
}

class SlideProcessResult {
  SlideProcessResult({
    required this.newSlide,
    required this.slideDetected,
    required this.clipCosine,
    this.textSimilarity,
    this.slideNumber,
    this.boundingBox,
    this.summary,
  });

  final bool newSlide;
  final bool slideDetected;
  final double clipCosine;
  final double? textSimilarity;
  final int? slideNumber;
  final List<SlidePoint>? boundingBox;
  final Map<String, dynamic>? summary;
}

class SlideImageAnalysis {
  const SlideImageAnalysis({
    required this.slideDetected,
    this.boundingBox,
    this.croppedImage,
    this.annotatedImage,
  });

  final bool slideDetected;
  final List<SlidePoint>? boundingBox;
  final Uint8List? croppedImage;
  final Uint8List? annotatedImage;
}

class SlideComparisonResult {
  SlideComparisonResult({
    required this.slide1,
    required this.slide2,
    required this.clipCosine,
    this.textSimilarity,
    required this.newSlide,
  });

  final SlideImageAnalysis slide1;
  final SlideImageAnalysis slide2;
  final double clipCosine;
  final double? textSimilarity;
  final bool newSlide;
}

class SlideClient {
  SlideClient({FastApiClient? apiClient})
    : _apiClient = apiClient ?? FastApiClient();

  final FastApiClient _apiClient;

  Future<SlideProcessResult> processSlide(Uint8List imageBytes) async {
    final response = await _apiClient.postImage(
      path: '/process_slide',
      imageBytes: imageBytes,
      contentType: 'image/jpeg',
    );

    if (response.statusCode != 200) {
      throw SlideClientException(
        'Slide processing failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SlideProcessResult(
      newSlide: payload['new_slide'] as bool? ?? false,
      slideDetected: payload['slide_detected'] as bool? ?? false,
      clipCosine: _toDouble(payload['clip_cosine']),
      textSimilarity: payload['text_similarity'] is num
          ? (payload['text_similarity'] as num).toDouble()
          : double.tryParse('${payload['text_similarity']}'),
      slideNumber: payload['slide_number'] is num
          ? (payload['slide_number'] as num).round()
          : int.tryParse('${payload['slide_number']}'),
      boundingBox: _parseBoundingBox(payload['bounding_box']),
      summary: payload['summary'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload['summary'] as Map)
          : null,
    );
  }

  Future<SlideComparisonResult> compareSlides(
    Uint8List imageA,
    Uint8List imageB,
  ) async {
    final response = await _apiClient.postImages(
      path: '/compare_slides',
      images: {'image1': imageA, 'image2': imageB},
      contentType: 'image/jpeg',
    );

    if (response.statusCode != 200) {
      throw SlideClientException(
        'Slide comparison failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;

    SlideImageAnalysis _parseSlide(String key) {
      final raw = payload[key];
      if (raw is! Map<String, dynamic>) {
        throw SlideClientException('Malformed response: missing $key');
      }
      return SlideImageAnalysis(
        slideDetected: raw['slide_detected'] as bool? ?? false,
        boundingBox: _parseBoundingBox(raw['bounding_box']),
        croppedImage: _decodeImage(raw['cropped_image_base64']),
        annotatedImage: _decodeImage(raw['annotated_image_base64']),
      );
    }

    final metrics = payload['metrics'] is Map<String, dynamic>
        ? payload['metrics'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return SlideComparisonResult(
      slide1: _parseSlide('slide1'),
      slide2: _parseSlide('slide2'),
      clipCosine: _toDouble(metrics['clip_cosine'] ?? payload['clip_cosine']),
      textSimilarity: metrics['text_similarity'] is num
          ? (metrics['text_similarity'] as num).toDouble()
          : double.tryParse(
              '${metrics['text_similarity'] ?? payload['text_similarity']}',
            ),
      newSlide: payload['new_slide'] as bool? ?? false,
    );
  }

  static double _toDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static Uint8List? _decodeImage(Object? data) {
    if (data is! String || data.isEmpty) {
      return null;
    }
    return base64Decode(data);
  }

  static List<SlidePoint>? _parseBoundingBox(Object? data) {
    if (data is! List) {
      return null;
    }

    final points = <SlidePoint>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final x = _toDouble(entry['x']);
      final y = _toDouble(entry['y']);
      points.add(SlidePoint(x: x, y: y));
    }
    if (points.isEmpty) {
      return null;
    }
    return points;
  }
}

class SlideClientException implements Exception {
  SlideClientException(this.message);

  final String message;

  @override
  String toString() => 'SlideClientException: $message';
}
