class SlideRepository {
  Map<String, dynamic>? _latestSummary;
  int? _latestSlideNumber;

  Map<String, dynamic>? get latestSummary => _latestSummary;
  int? get latestSlideNumber => _latestSlideNumber;

  bool get hasSummary => _latestSummary != null;

  void save({required Map<String, dynamic> summary, int? slideNumber}) {
    _latestSummary = summary;
    _latestSlideNumber = slideNumber;
  }

  void reset() {
    _latestSummary = null;
    _latestSlideNumber = null;
  }
}
