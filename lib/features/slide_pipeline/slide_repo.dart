import 'dart:collection';

/// Snapshot of a slide summary with optional metadata.
class SlideSummaryContext {
  SlideSummaryContext({
    required Map<String, dynamic> summary,
    this.slideNumber,
    DateTime? capturedAt,
  })  : summary = Map<String, dynamic>.from(summary),
        capturedAt = capturedAt ?? DateTime.now();

  /// Summary payload returned from the backend for this slide.
  final Map<String, dynamic> summary;

  /// The slide number assigned by the backend, if available.
  final int? slideNumber;

  /// Timestamp when this summary was recorded.
  final DateTime capturedAt;
}

class SlideRepository {
  static const int _maxHistoryEntries = 20;

  SlideSummaryContext? _current;
  final List<SlideSummaryContext> _history = <SlideSummaryContext>[];

  Map<String, dynamic>? get latestSummary => _current?.summary;
  int? get latestSlideNumber => _current?.slideNumber;

  bool get hasSummary => _current != null;

  SlideSummaryContext? get currentContext => _current;
  UnmodifiableListView<SlideSummaryContext> get history =>
      UnmodifiableListView(_history);

  /// Update the active slide summary. When [isNewSlide] is true the snapshot
  /// is appended to the history; otherwise the most recent history entry is
  /// replaced so that the "current slide" always reflects the latest payload.
  SlideSummaryContext? updateCurrent({
    required Map<String, dynamic> summary,
    int? slideNumber,
    bool isNewSlide = false,
  }) {
    final snapshot = SlideSummaryContext(
      summary: summary,
      slideNumber: slideNumber,
    );
    _current = snapshot;

    if (_history.isEmpty) {
      _history.add(snapshot);
    } else if (isNewSlide) {
      _history.add(snapshot);
      if (_history.length > _maxHistoryEntries) {
        _history.removeAt(0);
      }
    } else {
      _history[_history.length - 1] = snapshot;
    }

    return _current;
  }

  /// Resolve which slide context should be used to answer [question]. The
  /// current slide is returned by default; explicit mentions of "previous"
  /// or "two slides ago" choose from the history when available.
  SlideSummaryContext? resolveContext(String question) {
    if (_current == null) {
      return null;
    }

    final normalized = question.toLowerCase();

    bool containsAny(Iterable<String> needles) =>
        needles.any((needle) => normalized.contains(needle));

    SlideSummaryContext? historyFromEnd(int positionFromEnd) {
      if (positionFromEnd < 1 || positionFromEnd > _history.length) {
        return null;
      }
      return _history[_history.length - positionFromEnd];
    }

    // Explicit references to the current slide take priority.
    if (containsAny({'current slide', 'this slide', 'right now', 'current'})) {
      return _current;
    }

    // Handle "two slides ago" variations before generic "previous".
    if (containsAny({
      'two slides ago',
      '2 slides ago',
      'two slides back',
      'second previous slide',
      'before last slide',
    })) {
      return historyFromEnd(3) ?? historyFromEnd(2) ?? _current;
    }

    if (containsAny({
      'previous slide',
      'previous one',
      'last slide',
      'prior slide',
      'earlier slide',
    })) {
      return historyFromEnd(2) ?? _current;
    }

    return _current;
  }

  void save({required Map<String, dynamic> summary, int? slideNumber}) {
    updateCurrent(
      summary: summary,
      slideNumber: slideNumber,
      isNewSlide: true,
    );
  }

  void reset() {
    _current = null;
    _history.clear();
  }
}
