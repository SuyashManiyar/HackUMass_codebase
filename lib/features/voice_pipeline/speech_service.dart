import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Handles on-device speech recognition and text-to-speech.
class LocalSpeechService {
  LocalSpeechService({
    SpeechToText? speechToText,
    FlutterTts? flutterTts,
  })  : _speechToText = speechToText ?? SpeechToText(),
        _flutterTts = flutterTts ?? FlutterTts();

  final SpeechToText _speechToText;
  final FlutterTts _flutterTts;

  final StreamController<bool> _speakingController =
      StreamController<bool>.broadcast();

  bool _isInitialized = false;
  String _finalText = '';
  bool _isSpeaking = false;

  Stream<bool> get speakingStream => _speakingController.stream;
  bool get isInitialized => _isInitialized;
  bool get isListening => _speechToText.isListening;
  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    _isInitialized = await _speechToText.initialize();
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> startListening(
    void Function(String text, bool isFinal) onResult,
  ) async {
    if (!_isInitialized) return;
    _finalText = '';

    await _speechToText.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        if (result.finalResult) {
          _finalText = words;
        }
        onResult(words, result.finalResult);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  Future<String> stopListening() async {
    await _speechToText.stop();
    await Future.delayed(const Duration(milliseconds: 100));
    return _finalText;
  }

  Future<void> cancelListening() async {
    await _speechToText.cancel();
    _finalText = '';
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _isSpeaking = true;
    _speakingController.add(true);
    try {
      await _flutterTts.speak(trimmed);
    } finally {
      _isSpeaking = false;
      _speakingController.add(false);
    }
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
    if (_isSpeaking) {
      _isSpeaking = false;
      _speakingController.add(false);
    }
  }

  Future<void> dispose() async {
    await _speechToText.cancel();
    await _flutterTts.stop();
    await _speakingController.close();
  }
}

