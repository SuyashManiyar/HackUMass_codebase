import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;
  String _finalText = '';

  Future<void> initialize() async {
    _speechEnabled = await _speechToText.initialize();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  bool get isInitialized => _speechEnabled;
  bool get isListening => _speechToText.isListening;
  bool get isNotListening => _speechToText.isNotListening;

  Future<void> startListening(Function(String, bool) onResult) async {
    if (!_speechEnabled) return;

    _finalText = '';

    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          _finalText = result.recognizedWords;
          onResult(result.recognizedWords, true);
        } else {
          onResult(result.recognizedWords, false);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  Future<String> stopListening() async {
    await _speechToText.stop();
    await Future.delayed(const Duration(milliseconds: 100));
    return _finalText;
  }

  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
  }
}