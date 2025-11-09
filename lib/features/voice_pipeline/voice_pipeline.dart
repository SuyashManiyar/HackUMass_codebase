import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../llm/llm_service.dart';
import 'stt/elevenlabs_stt_service.dart';
import 'stt/voice_recorder.dart';
import 'tts/audio_playback_controller.dart';
import 'tts/elevenlabs_tts_service.dart';

/// Coordinates the STT → LLM → TTS pipeline using ElevenLabs and OpenRouter.
class VoicePipeline {
  VoicePipeline({
    required this.recorder,
    required this.sttService,
    required this.llmService,
    required this.ttsService,
    AudioPlaybackController? audioController,
  }) : _audio = audioController ?? AudioPlaybackController() {
    _playerCompleteSub = _audio.player.onPlayerComplete.listen(
      (_) => _isPlaying = false,
    );
  }

  final VoiceRecorder recorder;
  final ElevenLabsSttService sttService;
  final LlmService llmService;
  final ElevenLabsTtsService ttsService;
  final AudioPlaybackController _audio;
  StreamSubscription<void>? _playerCompleteSub;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isPlaying = false;
  bool _canceled = false;

  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isPlaying => _isPlaying;

  Future<void> startRecording() async {
    await _audio.stop();
    _canceled = false;
    await recorder.start();
    _isRecording = true;
  }

  Future<VoicePipelineResult> stopAndProcess({
    required Map<String, dynamic> slideSummary,
  }) async {
    if (!_isRecording) {
      throw const VoicePipelineException('Recording was not started.');
    }

    _isProcessing = true;
    final File audioFile = await recorder.stop();
    _isRecording = false;

    try {
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      final transcript = (await sttService.transcribeFile(audioFile)).trim();
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      if (transcript.isEmpty) {
        _isPlaying = false;
        return const VoicePipelineResult(transcript: '', answer: '');
      }

      final String answer = await llmService.fetchAnswer(
        userQuestion: transcript,
        slideSummary: slideSummary,
      );
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      final Uint8List audioBytes = await ttsService.synthesize(text: answer);
      if (_canceled) {
        throw const VoicePipelineException('Canceled');
      }

      await _audio.stop();
      _isPlaying = true;
      unawaited(
        _audio.playBytes(audioBytes).whenComplete(() {
          _isPlaying = false;
        }),
      );

      return VoicePipelineResult(transcript: transcript, answer: answer);
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
      try {
        await recorder.stop();
      } catch (_) {
        // Ignore errors when stopping a recorder that may already be stopped.
      }
      _isRecording = false;
    }
    _isProcessing = false;
    _isPlaying = false;
    await _audio.stop();
  }

  Future<void> dispose() async {
    await recorder.dispose();
    sttService.dispose();
    ttsService.dispose();
    llmService.dispose();
    await _playerCompleteSub?.cancel();
    await _audio.dispose();
  }
}

class VoicePipelineResult {
  const VoicePipelineResult({required this.transcript, required this.answer});

  final String transcript;
  final String answer;
}

class VoicePipelineException implements Exception {
  const VoicePipelineException(this.message);

  final String message;

  @override
  String toString() => 'VoicePipelineException: $message';
}


