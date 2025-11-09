import 'package:flutter/foundation.dart';

/// Central app state for slide summaries and OCR context.
class AppState extends ChangeNotifier {
  Map<String, dynamic>? _latestSummary;
  String _latestOcr = '';
  bool _isProcessingSlide = false;

  Map<String, dynamic>? get latestSummary => _latestSummary;
  String get latestOcr => _latestOcr;
  bool get isProcessingSlide => _isProcessingSlide;

  void setProcessing(bool value) {
    if (_isProcessingSlide == value) return;
    _isProcessingSlide = value;
    notifyListeners();
  }

  void updateSlide({
    required Map<String, dynamic> summary,
    required String ocrText,
  }) {
    _latestSummary = summary;
    _latestOcr = ocrText;
    notifyListeners();
  }

  void resetSlide() {
    _latestSummary = null;
    _latestOcr = '';
    notifyListeners();
  }
}


