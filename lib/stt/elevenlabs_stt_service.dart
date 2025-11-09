import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ElevenLabs speech-to-text helper that uploads an audio file and
/// returns the transcribed text.
class ElevenLabsSttService {
  ElevenLabsSttService({
    required this.apiKey,
    this.modelId = 'scribe_v1',
    this.languageCode = 'en',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String modelId;
  final String languageCode;
  final http.Client _httpClient;

  /// Sends [audioFile] to ElevenLabs' transcription endpoint.
  ///
  /// The API currently accepts common formats such as WAV and MP3.
  Future<String> transcribeFile(File audioFile) async {
    if (!audioFile.existsSync()) {
      throw ElevenLabsException('Audio file does not exist: ${audioFile.path}');
    }

    final uri = Uri.parse('https://api.elevenlabs.io/v1/speech-to-text');

    final request = http.MultipartRequest('POST', uri)
      ..headers['xi-api-key'] = apiKey
      ..fields['model_id'] = modelId
      ..fields['language_code'] = languageCode
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw ElevenLabsException(
        'STT request failed (${response.statusCode}): ${response.body}',
      );
    }

    final Map<String, dynamic> payload = jsonDecode(response.body);
    final text = payload['text'];
    if (text is! String) {
      throw ElevenLabsException('Unexpected STT payload: ${response.body}');
    }
    final cleaned = text.trim();
    return cleaned;
  }

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
