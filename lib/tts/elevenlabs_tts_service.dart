import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thin client for ElevenLabs text-to-speech REST API.
///
/// Usage:
/// ```dart
/// final service = ElevenLabsTtsService(apiKey: yourKey);
/// final audioBytes = await service.synthesize(text: 'Hello there!');
/// ```
class ElevenLabsTtsService {
  ElevenLabsTtsService({
    required this.apiKey,
    this.voiceId = '21m00Tcm4TlvDq8ikWAM',
    this.modelId = 'eleven_multilingual_v2',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String voiceId;
  final String modelId;
  final http.Client _httpClient;

  /// Generates audio bytes (MPEG) for [text].
  Future<Uint8List> synthesize({
    required String text,
    Map<String, dynamic>? voiceSettings,
  }) async {
    final uri = Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId');

    final response = await _httpClient.post(
      uri,
      headers: {
        'xi-api-key': apiKey,
        'Accept': 'audio/mpeg',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model_id': modelId,
        'text': text,
        if (voiceSettings != null) 'voice_settings': voiceSettings,
      }),
    );

    if (response.statusCode != 200) {
      throw ElevenLabsException(
        'TTS request failed (${response.statusCode}): ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  /// Dispose of the underlying HTTP client if one was created internally.
  void dispose() {
    _httpClient.close();
  }
}

class ElevenLabsException implements Exception {
  ElevenLabsException(this.message);

  final String message;

  @override
  String toString() => 'ElevenLabsException: $message';
}

