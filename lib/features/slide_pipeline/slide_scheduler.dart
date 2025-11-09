import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/app_state.dart';
import '../../core/env.dart';
import '../camera/camera_capture_service.dart';
import 'slide_client.dart';
import 'slide_repo.dart';

class SlideScheduler {
  SlideScheduler({
    required CameraCaptureService camera,
    required SlideClient client,
    required SlideRepository repository,
    required AppState appState,
    Duration? interval,
  }) : _camera = camera,
       _client = client,
       _repository = repository,
       _appState = appState,
       _interval = interval ?? Env.slideCaptureInterval;

  final CameraCaptureService _camera;
  final SlideClient _client;
  final SlideRepository _repository;
  final AppState _appState;
  final Duration _interval;

  Timer? _timer;
  bool _isProcessing = false;

  bool get isRunning => _timer != null;

  void start() {
    if (isRunning) return;
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_isProcessing) return;

    final Uint8List? frame = await _camera.captureFrame();
    if (frame == null) {
      debugPrint('SlideScheduler: captureFrame returned null.');
      return;
    }

    _isProcessing = true;
    _appState.setProcessing(true);

    try {
      final result = await _client.processSlide(frame);
      final summary = result.summary;
      if (summary != null) {
        if (result.newSlide || !_repository.hasSummary) {
          _repository.save(summary: summary, slideNumber: result.slideNumber);
        }
        final latest = _repository.latestSummary ?? summary;
        final latestNumber =
            _repository.latestSlideNumber ?? result.slideNumber;
        _appState.updateSlide(summary: latest, slideNumber: latestNumber);
      }
    } catch (error, stackTrace) {
      debugPrint('SlideScheduler: failed to process slide - $error');
      debugPrint('$stackTrace');
    } finally {
      _appState.setProcessing(false);
      _isProcessing = false;
    }
  }
}
