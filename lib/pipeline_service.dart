import 'dart:convert';
import 'package:http/http.dart' as http;
import 'speech_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PipelineService {
  final SpeechService _speechService = SpeechService();
  bool _isListening = false;
  String _currentTranscription = '';

  Future<void> initialize() async {
    await _speechService.initialize();
  }

  bool get isInitialized => _speechService.isInitialized;
  bool get isListening => _isListening;

  Future<void> startPipeline(String imageSummary, Function(String) onTranscriptionUpdate) async {
    _isListening = true;
    _currentTranscription = '';

    await _speechService.startListening((text, isFinal) {
      _currentTranscription = text;
      onTranscriptionUpdate(text);
    });
  }

  Future<void> stopPipelineAndProcess(String imageSummary) async {
    _isListening = false;

    final finalTranscription = await _speechService.stopListening();
    final transcriptionToUse = finalTranscription.isNotEmpty ? finalTranscription : _currentTranscription;

    if (transcriptionToUse.isEmpty) return;

    final llmResponse = await _callLLM(transcriptionToUse, imageSummary);

    await _speechService.speak(llmResponse);
  }

  Future<String> _callLLM(String transcription, String imageSummary) async {
    final openRouterApiKey = dotenv.env['OPNRTR_API_KEY']!;

    final prompt ='''
You are an AI assistant answering a user's question about a presentation slide.
You will be given a JSON object with all known slide content.

CRITICAL CONSTRAINT: Your response will be converted to audio. It MUST NOT EXCEED 25 WORDS (8-10 seconds).

Instructions:
1.  Answer the question directly. No "Hello" or "Sure". Do not say "According to the JSON...".
2.  First, try to answer using only the $imageSummary.
3.  If the $imageSummary doesn't have the answer, but the question is *related* to the slide's topic, use your general knowledge for a brief answer.
4.  If the question is completely *unrelated* to the slide, you must respond with: "It's not covered in the slides."

JSON Context:
$imageSummary

User Question:
$transcription

Your 10-Second Answer (25 words max):
''';

    try {
      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openRouterApiKey',
          'HTTP-Referer': 'https://github.com/yourusername/yourapp',
          'X-Title': 'SlideScribe App',
        },
        body: jsonEncode({
          'model': 'openai/gpt-4o-mini',
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] ?? 'I could not generate a response.';
      } else {
        print('OpenRouter Error: ${response.statusCode} - ${response.body}');
        return 'Error: ${response.statusCode}';
      }
    } catch (e) {
      print('LLM Error: $e');
      return 'Error calling LLM: $e';
    }
  }

  void dispose() {
    _speechService.dispose();
  }
}