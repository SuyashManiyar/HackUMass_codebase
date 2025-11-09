import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  const Env._();

  static String get fastApiBaseUrl =>
      dotenv.env['FASTAPI_BASE_URL'] ?? 'http://127.0.0.1:8000';

  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['OPENROUTER_API_KEY'] ?? '';

  static String get openRouterApiKey => dotenv.env['OPENROUTER_API_KEY'] ?? '';

  static String get elevenLabsApiKey => dotenv.env['ELEVENLABS_API_KEY'] ?? '';

  static String get signalingServerUrl =>
      dotenv.env['SIGNALING_SERVER_URL'] ?? 'http://127.0.0.1:3000';

  static Duration get slideCaptureInterval {
    final seconds = int.tryParse(dotenv.env['SLIDE_CAPTURE_INTERVAL'] ?? '');
    return Duration(seconds: seconds ?? 10);
  }
}


