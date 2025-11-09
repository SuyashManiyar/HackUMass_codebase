class SlideRepository {
  Map<String, dynamic>? _latestSummary;

  Map<String, dynamic>? get latestSummary => _latestSummary;

  bool get hasSummary => _latestSummary != null;

  void save({required Map<String, dynamic> summary}) {
    _latestSummary = summary;
  }

  void reset() {
    _latestSummary = null;
  }
}
