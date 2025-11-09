import 'dart:async';

import '../../core/env.dart';
import '../llm/llm_service.dart';
import '../slide_pipeline/slide_repo.dart';
import 'speech_service.dart';
import 'voice_pipeline.dart';

/// Coordinates the voice pipeline behind a single [run] call.
class ConversationController {
  ConversationController({
    required SlideRepository repository,
    LocalSpeechService? speechService,
    LlmService? llmService,
  })  : _speech = speechService ?? LocalSpeechService(),
        _llm = llmService ?? LlmService(baseUrl: Env.fastApiBaseUrl),
        _repository = repository {
    _pipeline = VoicePipeline(
      speechService: _speech,
      llmService: _llm,
    );
    _active = this;
  }

  static ConversationController? _active;

  static ConversationController? get active => _active;

  final LocalSpeechService _speech;
  final LlmService _llm;
  final SlideRepository _repository;
  late final VoicePipeline _pipeline;

  bool _isRecording = false;
  bool _isProcessing = false;
  Timer? _recordingTimer;

  static const Duration _maxRecordingDuration = Duration(seconds: 12);

  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isPlaying => _pipeline.isPlaying;
  Stream<bool> get speakingStream => _pipeline.speakingStream;

  Future<void> _ensureInitialized() async {
    if (!_speech.isInitialized) {
      await _speech.initialize();
    }
  }

  Future<void> start() async {
    if (_isRecording) return;
    if (_isProcessing) {
      await interrupt();
    }
    if (_pipeline.isPlaying) {
      await interrupt();
    }

    await _ensureInitialized();

    await _pipeline.startRecording();
    _isRecording = true;
    _recordingTimer?.cancel();
    _recordingTimer = Timer(_maxRecordingDuration, () async {
      if (_isRecording) {
        await interrupt();
        // ignore: avoid_print
        print('Recording stopped after reaching max duration.');
      }
    });
  }

  Future<VoicePipelineResult?> stop() async {
    if (!_isRecording || _isProcessing) return null;

    _isRecording = false;
    _isProcessing = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      if (!_repository.hasSummary) {
        throw const VoicePipelineException(
          'No slide summary captured yet. Capture a slide before asking questions.',
        );
      }

      final result = await _pipeline.stopAndProcess(
        resolveContext: (question) => _repository.resolveContext(question),
      );

      // ignore: avoid_print
      print('Transcript: ${result.transcript}');
      // ignore: avoid_print
      print('Answer: ${result.answer}');
      if (result.slideContext?.slideNumber != null) {
        // ignore: avoid_print
        print('Resolved slide #: ${result.slideContext!.slideNumber}');
      }

      return result;
    } on VoicePipelineException catch (error) {
      if (error.message == 'Canceled') {
        return null;
      }
      rethrow;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> interrupt() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _pipeline.cancel();
    _isRecording = false;
    _isProcessing = false;
  }

  Future<void> dispose() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _pipeline.dispose();
    if (identical(_active, this)) {
      _active = null;
    }
  }
}
