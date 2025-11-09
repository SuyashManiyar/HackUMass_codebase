import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin OpenRouter client that sends the user's utterance and slide summary
/// to a lightweight LLM and returns the generated answer.
class LlmService {
  LlmService({
    required this.apiKey,
    this.model = 'openai/gpt-4o-mini',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _httpClient;

  /// Sends [userQuestion] paired with [slideSummary] to OpenRouter's chat endpoint.
  Future<String> fetchAnswer({
    required String userQuestion,
    required Map<String, dynamic> slideSummary,
  }) async {
    final String encodedSummary = _prepareSummary(slideSummary);
    final prompt = '''
<context>
$encodedSummary
</context>

<question>
$userQuestion
</question>

Respond in clear, concise English using the context when relevant.
''';

    try {
      final response = await _httpClient
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are a helpful slide tutor. Always answer concisely in English.',
                },
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.4,
              'max_tokens': 256,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw LlmException(
          'LLM request failed (${response.statusCode}): ${response.body}',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = payload['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw const LlmException('LLM response missing choices.');
      }

      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const LlmException('LLM response missing message content.');
      }

      return content.trim();
    } on TimeoutException {
      throw const LlmException('LLM request timed out.');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

const int _maxSummaryChars = 2000;

String _prepareSummary(Map<String, dynamic> summary) {
  final encoded = jsonEncode(summary);
  if (encoded.length <= _maxSummaryChars) {
    return encoded;
  }
  return encoded.substring(0, _maxSummaryChars) + '…';
}

class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => 'LlmException: $message';
}


