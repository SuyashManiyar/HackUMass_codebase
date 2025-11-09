class SlideRepository {
  Map<String, dynamic>? _latestSummary;
  String _latestOcr = '';

  Map<String, dynamic>? get latestSummary => _latestSummary;
  String get latestOcr => _latestOcr;

  bool get hasSummary => _latestSummary != null;

  void save({
    required Map<String, dynamic> summary,
    String ocrText = '',
  }) {
    _latestSummary = summary;
    _latestOcr = ocrText;
  }

  void reset() {
    _latestSummary = null;
    _latestOcr = '';
  }
}


