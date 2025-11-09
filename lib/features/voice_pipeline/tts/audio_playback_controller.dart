import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight wrapper around [AudioPlayer] for playing TTS audio on device.
class AudioPlaybackController {
  AudioPlaybackController({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  AudioPlayer get player => _player;

  Future<void> playBytes(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );

    await file.writeAsBytes(bytes, flush: true);

    await _player.stop();
    await _player.play(DeviceFileSource(file.path, mimeType: 'audio/mpeg'));
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}


