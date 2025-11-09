import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/env.dart';

/// Client that proxies user questions to the FastAPI backend, which enforces
/// slide-aware context and guardrails before querying Gemini.
class LlmService {
  LlmService({http.Client? httpClient, String? baseUrl})
    : _httpClient = httpClient ?? http.Client(),
      _baseUri = Uri.parse(baseUrl ?? Env.fastApiBaseUrl);

  final http.Client _httpClient;
  final Uri _baseUri;

  /// Sends [userQuestion] (and optionally [slideSummary]) to the backend ask
  /// endpoint and returns the generated answer.
  Future<String> fetchAnswer({
    required String userQuestion,
    required Map<String, dynamic> slideSummary,
  }) async {
    final uri = _baseUri.resolve('/ask');
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'question': userQuestion,
              'slide_summary': slideSummary,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw LlmException(
          'Backend request failed (${response.statusCode}): ${response.body}',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = payload['answer'];
      if (answer is! String || answer.trim().isEmpty) {
        throw const LlmException('Backend response missing answer text.');
      }

      return answer.trim();
    } on TimeoutException {
      throw const LlmException('Backend request timed out.');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => 'LlmException: $message';
}
