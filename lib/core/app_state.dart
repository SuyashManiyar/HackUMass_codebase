import 'package:flutter/foundation.dart';

/// Central app state for slide summaries and OCR context.
class AppState extends ChangeNotifier {
  Map<String, dynamic>? _latestSummary;
  int? _latestSlideNumber;
  bool _isProcessingSlide = false;

  Map<String, dynamic>? get latestSummary => _latestSummary;
  int? get latestSlideNumber => _latestSlideNumber;
  bool get isProcessingSlide => _isProcessingSlide;

  void setProcessing(bool value) {
    if (_isProcessingSlide == value) return;
    _isProcessingSlide = value;
    notifyListeners();
  }

  void updateSlide({required Map<String, dynamic> summary, int? slideNumber}) {
    _latestSummary = summary;
    _latestSlideNumber = slideNumber;
    notifyListeners();
  }

  void resetSlide() {
    _latestSummary = null;
    _latestSlideNumber = null;
    notifyListeners();
  }
}
