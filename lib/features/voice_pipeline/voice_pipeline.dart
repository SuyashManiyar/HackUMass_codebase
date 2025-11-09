import 'dart:async';
import '../llm/llm_service.dart';
import '../slide_pipeline/slide_repo.dart';
import 'speech_service.dart';

/// Coordinates the STT → LLM → TTS pipeline using on-device services.
class VoicePipeline {
  VoicePipeline({
    required this.speechService,
    required this.llmService,
  });

  final LocalSpeechService speechService;
  final LlmService llmService;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _canceled = false;

  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isPlaying => speechService.isSpeaking;

  Stream<bool> get speakingStream => speechService.speakingStream;

  Future<void> startRecording({
    void Function(String text, bool isFinal)? onPartialTranscript,
  }) async {
    _canceled = false;
    await speechService.startListening(
      (text, isFinal) => onPartialTranscript?.call(text, isFinal),
    );
    _isRecording = true;
  }

  Future<VoicePipelineResult> stopAndProcess({
    required SlideSummaryContext? Function(String question) resolveContext,
  }) async {
    if (!_isRecording) {
      throw const VoicePipelineException('Listening was not started.');
    }

    _isProcessing = true;
    final String transcript = (await speechService.stopListening()).trim();
    _isRecording = false;

    try {
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      if (transcript.isEmpty) {
        return const VoicePipelineResult(transcript: '', answer: '');
      }

      final SlideSummaryContext? context = resolveContext(transcript);
      final summaryForAnswer = context?.summary ?? const <String, dynamic>{};

      final String answer = await llmService.fetchAnswer(
        userQuestion: transcript,
        slideSummary: summaryForAnswer,
      );
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      await speechService.speak(answer);

      return VoicePipelineResult(
        transcript: transcript,
        answer: answer,
        slideContext: context,
      );
    } on VoicePipelineException {
      rethrow;
    } finally {
      _isProcessing = false;
      _canceled = false;
    }
  }

  Future<void> cancel() async {
    _canceled = true;
    if (_isRecording) {
      await speechService.cancelListening();
      _isRecording = false;
    }
    _isProcessing = false;
    await speechService.stopSpeaking();
  }

  Future<void> dispose() async {
    await speechService.dispose();
    llmService.dispose();
  }
}

class VoicePipelineResult {
  const VoicePipelineResult({
    required this.transcript,
    required this.answer,
    this.slideContext,
  });

  final String transcript;
  final String answer;
  final SlideSummaryContext? slideContext;
}

class VoicePipelineException implements Exception {
  const VoicePipelineException(this.message);

  final String message;

  @override
  String toString() => 'VoicePipelineException: $message';
}


