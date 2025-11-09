import 'dart:convert';
import 'dart:typed_data';

import '../../services/fastapi_client.dart';

class SlideProcessResult {
  SlideProcessResult({
    required this.changed,
    required this.slideDetected,
    required this.summary,
  });

  final bool changed;
  final bool slideDetected;
  final Map<String, dynamic>? summary;
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
    final summary = payload['summary'];
    return SlideProcessResult(
      changed: payload['changed'] as bool? ?? false,
      slideDetected: payload['slide_detected'] as bool? ?? false,
      summary: summary is Map<String, dynamic>
          ? Map<String, dynamic>.from(summary)
          : null,
    );
  }
}

class SlideClientException implements Exception {
  SlideClientException(this.message);

  final String message;

  @override
  String toString() => 'SlideClientException: $message';
}


