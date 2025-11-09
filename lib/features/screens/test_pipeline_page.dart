import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/env.dart';
import '../slide_pipeline/slide_repo.dart';
import '../voice_pipeline/conversation_controller.dart';

class TestPipelinePage extends StatefulWidget {
  const TestPipelinePage({
    super.key,
    required this.repository,
    required this.summary,
  });

  final SlideRepository repository;
  final Map<String, dynamic> summary;

  @override
  State<TestPipelinePage> createState() => _TestPipelinePageState();
}

class _TestPipelinePageState extends State<TestPipelinePage> {
  ConversationController? _controller;
  StreamSubscription<bool>? _speakingSub;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isSpeaking = false;

  String _status = 'Idle';
  String? _transcript;
  String? _answer;
  String? _error;
  late String _summaryText;
  String? _contextSummaryText;
  int? _resolvedSlideNumber;

  @override
  void initState() {
    super.initState();
    _summaryText = const JsonEncoder.withIndent('  ').convert(widget.summary);

    final elevenLabsKey = Env.elevenLabsApiKey;
    final openRouterKey = Env.openRouterApiKey;

    if (elevenLabsKey.isEmpty || openRouterKey.isEmpty) {
      _error = 'Missing ElevenLabs or OpenRouter API key. Check your .env file.';
      return;
    }

    try {
      _controller = ConversationController(repository: widget.repository);
      _speakingSub = _controller!.speakingStream.listen((isSpeaking) {
        if (!mounted) return;
        setState(() {
          _isSpeaking = isSpeaking;
          if (isSpeaking) {
            _status = 'Speaking…';
          } else if (!_controller!.isRecording && !_controller!.isProcessing) {
            _status = 'Idle';
          }
        });
      });
    } catch (error) {
      _error = error.toString();
    }
  }

  Future<void> _handleTap() async {
    final controller = _controller;
    if (controller == null) return;

    if (_isProcessing) {
      await controller.interrupt();
      setState(() {
        _isProcessing = false;
        _isRecording = false;
        _isSpeaking = false;
        _status = 'Interrupted';
      });
      return;
    }

    if (controller.isRecording) {
      await _stopAndProcess();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _isRecording = true;
      _isProcessing = false;
      _status = 'Listening…';
      _error = null;
      _transcript = null;
      _answer = null;
      _isSpeaking = false;
    });

    try {
      await controller.start();
    } catch (error) {
      setState(() {
        _isRecording = false;
        _status = 'Error starting recording';
        _error = error.toString();
      });
    }
  }

  Future<void> _stopAndProcess() async {
    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _status = 'Processing…';
    });

    try {
      final result = await controller.stop();
      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        if (result != null) {
          _transcript = result.transcript;
          _answer = result.answer;
          final hasUtterance = result.transcript.trim().isNotEmpty;
          _resolvedSlideNumber = result.slideContext?.slideNumber;
          final contextSummary = result.slideContext?.summary;
          _contextSummaryText = contextSummary == null
              ? null
              : const JsonEncoder.withIndent('  ').convert(contextSummary);

          final activeSummary =
              widget.repository.currentContext?.summary ?? widget.summary;
          _summaryText =
              const JsonEncoder.withIndent('  ').convert(activeSummary);

          if (hasUtterance && (_controller!.isPlaying || _isSpeaking)) {
            _status = 'Speaking…';
            _isSpeaking = true;
          } else {
            _status = 'Idle';
            _isSpeaking = false;
          }
          _error = null;
        } else {
          _status = 'Idle';
          _isSpeaking = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Error';
        _error = error.toString();
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _speakingSub?.cancel();
    _speakingSub = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusIcon = () {
      if (_status.startsWith('Error')) {
        return Icons.error_outline;
      }
      switch (_status) {
        case 'Listening…':
          return Icons.mic;
        case 'Processing…':
          return Icons.autorenew;
        case 'Speaking…':
          return Icons.volume_up_outlined;
        default:
          return Icons.info_outline;
      }
    }();

    return Scaffold(
      appBar: AppBar(title: const Text('Pipeline Test')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller == null ? null : _handleTap,
        backgroundColor:
            _isRecording ? theme.colorScheme.error : theme.colorScheme.primary,
        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
        label: Text(_isRecording ? 'Stop' : 'Start'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  statusIcon,
                  color: _status.startsWith('Error')
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Status: $_status',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Slide Summary',
                              style: theme.textTheme.titleSmall,
                            ),
                            if (_resolvedSlideNumber != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Resolved slide: #$_resolvedSlideNumber',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              _summaryText,
                              style: theme.textTheme.bodySmall,
                            ),
                            if (_contextSummaryText != null &&
                                _contextSummaryText != _summaryText) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Context Used for Last Answer',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _contextSummaryText!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transcript',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(_transcript ?? '—'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Model Response',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(_answer ?? '—'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              Row(
                children: const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Working…'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


