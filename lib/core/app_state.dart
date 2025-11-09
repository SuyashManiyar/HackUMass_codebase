import 'package:flutter/foundation.dart';

/// Central app state for slide summaries and OCR context.
class AppState extends ChangeNotifier {
  Map<String, dynamic>? _latestSummary;
  bool _isProcessingSlide = false;

  Map<String, dynamic>? get latestSummary => _latestSummary;
  bool get isProcessingSlide => _isProcessingSlide;

  void setProcessing(bool value) {
    if (_isProcessingSlide == value) return;
    _isProcessingSlide = value;
    notifyListeners();
  }

  void updateSlide({required Map<String, dynamic> summary}) {
    _latestSummary = summary;
    notifyListeners();
  }

  void resetSlide() {
    _latestSummary = null;
    notifyListeners();
  }
}
