import 'dart:convert';
import 'package:http/http.dart' as http;
import 'speech_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PipelineService {
  final SpeechService speechService;
  bool _isListening = false;
  String _currentTranscription = '';

  PipelineService({SpeechService? speechService})
      : speechService = speechService ?? SpeechService();

  Future<void> initialize() async {
    await speechService.initialize();
  }

  bool get isInitialized => speechService.isInitialized;
  bool get isListening => _isListening;

  Future<void> startPipeline(
    String imageSummary,
    Function(String) onTranscriptionUpdate,
  ) async {
    _isListening = true;
    _currentTranscription = '';

    await speechService.startListening((text, isFinal) {
      _currentTranscription = text;
      onTranscriptionUpdate(text);
    });
  }

  Future<void> stopPipelineAndProcess(String imageSummary) async {
    _isListening = false;

    final finalTranscription = await speechService.stopListening();
    final transcriptionToUse =
        finalTranscription.isNotEmpty ? finalTranscription : _currentTranscription;

    if (transcriptionToUse.isEmpty) return;

    final llmResponse = await _callLLM(transcriptionToUse, imageSummary);

    await speechService.speak(llmResponse);
  }

  Future<String> _callLLM(String transcription, String imageSummary) async {
    final openRouterApiKey = dotenv.env['OPNRTR_API_KEY'] ?? '';

    if (openRouterApiKey.isEmpty) {
      return 'OpenRouter API key missing';
    }

    final prompt = '''
You are an AI assistant answering a user's question about a presentation slide. You will be given a JSON object that contains all the known information from the slide.

CRITICAL CONSTRAINT: Your response will be converted to audio and must be readable in 8-10 seconds. This means your answer MUST NOT EXCEED 25 WORDS.

Rules:
1.  Prioritize JSON First: Your first priority is to answer the question using only the `JSON Context`. If the JSON contains the answer, use it.
2.  Use World Knowledge (If Related): If the JSON cannot answer the question, but the question is related to the slide's topics (like its `title` or `summary`), you may use your general knowledge to provide a brief answer.
3.  Decline Unrelated Questions: If the question is not related to the slide's content at all (e.g., asking about the weather, sports, or a different topic), state: "That information isn't available on this slide."
4.  Be Direct: Answer the question immediately. Do not use pleasantries like "Hello" or "Sure!"
5.  Sound Natural: Do not say "According to the JSON..." or "The JSON summary says...".

JSON Context:
$imageSummary

User Question:
$transcription

Your 10-Second Answer (25 words max):''';

    try {
      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $openRouterApiKey',
          'HTTP-Referer': 'https://github.com/SuyashManiyar/HackUMass_codebase',
          'X-Title': 'HackUMass App',
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
        return data['choices'][0]['message']['content'] ??
            'I could not generate a response.';
      } else {
        print('OpenRouter Error: ${response.statusCode} - ${response.body}');
        return 'Error: ${response.statusCode}';
      }
    } catch (e) {
      print('LLM Error: $e');
      return 'Error calling LLM: $e';
    }
  }

  void startListening(Function(String, bool) onResult) {
    _isListening = true;
    _currentTranscription = '';
    speechService.startListening(onResult);
  }

  Future<String> stopListening() async {
    _isListening = false;
    final result = await speechService.stopListening();
    return result.isNotEmpty ? result : _currentTranscription;
  }

  String reverseText(String text) => text.split('').reversed.join('');

  Future<void> speakText(String text) async {
    await speechService.speak(text);
  }

  void dispose() {
    speechService.dispose();
  }
}