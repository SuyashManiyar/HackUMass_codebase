import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../core/env.dart';
import '../llm/llm_service.dart';
import 'stt/elevenlabs_stt_service.dart';
import 'stt/voice_recorder.dart';
import 'tts/audio_playback_controller.dart';
import 'tts/elevenlabs_tts_service.dart';
import 'voice_pipeline.dart';

/// Coordinates the voice pipeline behind a single [run] call.
class ConversationController {
  ConversationController({
    AudioPlaybackController? audioController,
    VoiceRecorder? recorder,
    ElevenLabsSttService? sttService,
    ElevenLabsTtsService? ttsService,
    LlmService? llmService,
  })  : _audio = audioController ?? AudioPlaybackController(),
        _recorder = recorder ?? VoiceRecorder(),
        _stt = sttService ?? ElevenLabsSttService(apiKey: Env.elevenLabsApiKey),
        _tts = ttsService ?? ElevenLabsTtsService(apiKey: Env.elevenLabsApiKey),
        _llm = llmService ?? LlmService(apiKey: Env.openRouterApiKey) {
    if (_stt.apiKey.isEmpty || _tts.apiKey.isEmpty || _llm.apiKey.isEmpty) {
      throw StateError('Missing API keys for voice pipeline');
    }

    _pipeline = VoicePipeline(
      recorder: _recorder,
      sttService: _stt,
      llmService: _llm,
      ttsService: _tts,
      audioController: _audio,
    );
    _active = this;
  }

  static ConversationController? _active;

  static ConversationController? get active => _active;

  final AudioPlaybackController _audio;
  final VoiceRecorder _recorder;
  final ElevenLabsSttService _stt;
  final ElevenLabsTtsService _tts;
  final LlmService _llm;
  late final VoicePipeline _pipeline;

  bool _isRecording = false;
  bool _isProcessing = false;
  Timer? _recordingTimer;

  static const Duration _maxRecordingDuration = Duration(seconds: 12);

  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isPlaying => _pipeline.isPlaying;
  Stream<bool> get speakingStream => _audio.player.onPlayerStateChanged.map(
        (state) => state == PlayerState.playing,
      );

  Future<void> start() async {
    if (_isRecording) return;
    if (_isProcessing) {
      await interrupt();
    }
    if (_pipeline.isPlaying) {
      await interrupt();
    }

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

  Future<VoicePipelineResult?> stop({
    required Map<String, dynamic> summary,
  }) async {
    if (!_isRecording || _isProcessing) return null;

    _isRecording = false;
    _isProcessing = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final result = await _pipeline.stopAndProcess(slideSummary: summary);

      // ignore: avoid_print
      print('Transcript: ${result.transcript}');
      // ignore: avoid_print
      print('Answer: ${result.answer}');

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


