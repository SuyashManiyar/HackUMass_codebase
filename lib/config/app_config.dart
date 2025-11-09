/// Application configuration
class AppConfig {
  // Signaling server configuration
  static const String signalingServerUrl = String.fromEnvironment(
    'SIGNALING_SERVER_URL',
    defaultValue: 'http://localhost:3000',
  );

  // Alternative server URLs for fallback
  static const List<String> fallbackServerUrls = [
    'http://192.168.1.100:3000', // Local network
    'http://10.0.2.2:3000',      // Android emulator
  ];

  // Connection timeout settings
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 3);
  static const int maxReconnectAttempts = 3;

  // Video quality settings
  static const int defaultVideoWidth = 1280;
  static const int defaultVideoHeight = 720;
  static const int videoFrameRate = 30;

  // Gemini AI configuration
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyBjB9hCO3CSmWB4IZrvPHev1gdcP3Dzh_0',
  );
  static const String geminiModel = 'gemini-2.5-flash';

  // Feature flags
  static const bool enableRemoteCamera = true;
  static const bool enableConnectionMonitoring = true;
  static const bool enableDebugLogging = true;

  /// Get the current signaling server URL
  static String getSignalingServerUrl() {
    return signalingServerUrl;
  }

  /// Get fallback server URLs
  static List<String> getFallbackServerUrls() {
    return fallbackServerUrls;
  }
}
