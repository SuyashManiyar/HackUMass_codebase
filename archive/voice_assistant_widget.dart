import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../stt/elevenlabs_stt_service.dart';
import '../stt/voice_recorder.dart';
import '../tts/audio_playback_controller.dart';
import '../tts/elevenlabs_tts_service.dart';

/// High-level widget that mirrors the Python record-and-transcribe flow using
/// ElevenLabs' APIs directly from Flutter.
class VoiceAssistantWidget extends StatefulWidget {
  const VoiceAssistantWidget({
    super.key,
    required this.fetchResponse,
    this.buttonLabel = 'Hold to ask',
    this.processingLabel = 'Processing…',
  });

  /// Callback invoked once a transcription is available. Should return the text
  /// response that will later be synthesized and played back.
  final Future<String> Function(String transcription) fetchResponse;

  final String buttonLabel;
  final String processingLabel;

  @override
  State<VoiceAssistantWidget> createState() => _VoiceAssistantWidgetState();
}

class _VoiceAssistantWidgetState extends State<VoiceAssistantWidget> {
  late final ElevenLabsSttService _sttService;
  late final ElevenLabsTtsService _ttsService;
  late final VoiceRecorder _recorder;
  late final AudioPlaybackController _player;

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _lastTranscript;
  String? _lastResponse;
  String? _error;

  @override
  void initState() {
    super.initState();
    final apiKey = dotenv.env['ELEVENLABS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      _error = 'Missing ELEVENLABS_API_KEY environment variable.';
    }
    _sttService = ElevenLabsSttService(apiKey: apiKey ?? '');
    _ttsService = ElevenLabsTtsService(apiKey: apiKey ?? '');
    _recorder = VoiceRecorder();
    _player = AudioPlaybackController();
  }

  @override
  void dispose() {
    _player.dispose();
    _ttsService.dispose();
    _sttService.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_error != null) return;
    if (_isProcessing) return;

    setState(() {
      _error = null;
    });

    try {
      if (_isRecording) {
        setState(() => _isProcessing = true);
        final File audioFile = await _recorder.stop();
        setState(() => _isRecording = false);

        final transcription = await _sttService.transcribeFile(audioFile);
        setState(() => _lastTranscript = transcription);

        final responseText = await widget.fetchResponse(transcription);
        setState(() => _lastResponse = responseText);

        final audioBytes = await _ttsService.synthesize(text: responseText);
        await _player.playBytes(audioBytes);
      } else {
        await _recorder.start();
        setState(() => _isRecording = true);
      }
    } on Exception catch (err) {
      setState(() => _error = err.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: _toggleRecording,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isRecording ? theme.colorScheme.error : null,
          ),
          child: _isProcessing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(widget.processingLabel),
                  ],
                )
              : Text(_isRecording ? 'Release to stop' : widget.buttonLabel),
        ),
        if (_lastTranscript != null) ...[
          const SizedBox(height: 12),
          Text(
            'Transcript: $_lastTranscript',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_lastResponse != null) ...[
          const SizedBox(height: 8),
          Text(
            'Response: $_lastResponse',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

