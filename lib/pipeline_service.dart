import 'dart:typed_data';
import 'speech_service.dart';
import 'gemini_service.dart';

class PipelineService {
  final SpeechService _speechService = SpeechService();
  bool _isListening = false;
  bool _isProcessing = false;

  Future<void> initialize() async {
    await _speechService.initialize();
  }

  bool get isInitialized => _speechService.isInitialized;
  bool get isListening => _isListening;
  bool get isProcessing => _isProcessing;

  Future<void> startListening(Function(String, bool) onResult) async {
    _isListening = true;
    _isProcessing = false;
    await _speechService.startListening(onResult);
  }

  Future<String> stopListening() async {
    if (!_isListening) return '';

    _isListening = false;
    _isProcessing = true;

    final finalText = await _speechService.stopListening();

    _isProcessing = false;
    return finalText;
  }

  Future<String> processFullPipeline(Uint8List imageBytes, String speechText) async {
    final geminiResult = await get_gemini_response(imageBytes);

    final llmInput = {
      'speech_text': speechText,
      'gemini_result': geminiResult,
    };

    final llmOutput = await _sendToLLM(llmInput);

    await _speechService.speak(llmOutput);

    return llmOutput;
  }

  Future<String> _sendToLLM(Map<String, dynamic> input) async {
    return input.toString();
  }

  String reverseText(String text) {
    return text.split('').reversed.join('');
  }

  Future<void> speakText(String text) async {
    await _speechService.speak(text);
  }

  Future<void> speakReversedText(String text) async {
    final reversed = reverseText(text);
    await _speechService.speak(reversed);
  }

  void dispose() {
    _speechService.dispose();
  }
}