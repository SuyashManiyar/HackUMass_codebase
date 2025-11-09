import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Utility wrapper for the `record` plugin that stores audio in the cache dir.
class VoiceRecorder {
  VoiceRecorder({
    AudioEncoder encoder = AudioEncoder.wav,
    int bitRate = 128000,
    int sampleRate = 44100,
  })  : _encoder = encoder,
        _bitRate = bitRate,
        _sampleRate = sampleRate,
        _recorder = AudioRecorder();

  final AudioEncoder _encoder;
  final int _bitRate;
  final int _sampleRate;
  final AudioRecorder _recorder;

  Future<bool> get isRecording => _recorder.isRecording();

  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const RecorderException('Microphone permission denied');
    }

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    final tempDir = await getTemporaryDirectory();
    final extension = _encoder == AudioEncoder.aacLc ? 'm4a' : 'wav';
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(tempDir.path, fileName);

    await _recorder.start(
      RecordConfig(
        encoder: _encoder,
        bitRate: _bitRate,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
      path: filePath,
    );
  }

  Future<File> recordFor({required int seconds}) async {
    await start();
    await Future.delayed(Duration(seconds: seconds));
    return stop();
  }

  Future<File> stop() async {
    final filePath = await _recorder.stop();
    if (filePath == null) {
      throw const RecorderException('No recording in progress');
    }
    return File(filePath);
  }

  Future<void> dispose() => _recorder.dispose();
}

class RecorderException implements Exception {
  const RecorderException(this.message);

  final String message;

  @override
  String toString() => 'RecorderException: $message';
}


