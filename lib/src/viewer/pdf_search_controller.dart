import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

// ---------------------------------------------------------------------------
// Internal notifier — exposes notifyListeners() publicly.
// ChangeNotifier.notifyListeners() is @protected, so a plain ChangeNotifier
// field cannot call it from outside the class hierarchy. This private
// subclass wraps it safely.
// ---------------------------------------------------------------------------
class _PublicNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Encapsulates all PDF text-search state and drives Syncfusion's native
/// search mechanism via [sf.PdfViewerController].
///
/// ### Usage
/// ```dart
/// searchController.search('flutter');  // synchronous in Syncfusion 27.x
/// searchController.nextResult();
/// searchController.previousResult();
/// searchController.clearSearch();
/// ```
///
/// ### Syncfusion 27.x API facts (confirmed from source)
/// - `PdfViewerController.searchText()` returns [sf.PdfTextSearchResult]
///   **synchronously** — it is NOT a Future.
/// - The search-option enum is [sfpdf.TextSearchOption], defined in
///   `syncfusion_flutter_pdf` (already a direct dependency), exported via
///   `package:syncfusion_flutter_pdf/pdf.dart`.
/// - [sf.PdfTextSearchResult] is a [ChangeNotifier] that fires whenever
///   Syncfusion updates `totalInstanceCount` (incremental page scan) or
///   `currentInstanceIndex` (next/prev navigation).
class PdfSearchController {
  PdfSearchController({required sf.PdfViewerController sfController})
      : _sfController = sfController;

  final sf.PdfViewerController _sfController;

  // ---------------------------------------------------------------------------
  // Notifier
  // ---------------------------------------------------------------------------

  final _PublicNotifier _notifier = _PublicNotifier();

  /// Listen to this to rebuild search-related UI only.
  /// Never fires during normal page swipes.
  ChangeNotifier get notifier => _notifier;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  sf.PdfTextSearchResult? _result;

  /// The raw Syncfusion search result. `null` when no search is active.
  sf.PdfTextSearchResult? get result => _result;

  String _query = '';

  /// The text currently being searched. Empty when no search is active.
  String get query => _query;

  /// `true` briefly while the internal state is being set up.
  /// (Syncfusion 27.x searchText() is synchronous so this is only true
  /// for the duration of the call itself.)
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// Whether a search is active.
  bool get hasActiveSearch => _query.isNotEmpty;

  /// Total matches found by the current search.
  /// Grows incrementally as Syncfusion scans the document page by page.
  int get totalCount => _result?.totalInstanceCount ?? 0;

  /// 1-based index of the currently highlighted match.
  int get currentIndex => _result?.currentInstanceIndex ?? 0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initiates a new search for [query].
  ///
  /// Calls `PdfViewerController.searchText()` which is **synchronous** in
  /// Syncfusion 27.x and returns a live [sf.PdfTextSearchResult] immediately.
  /// The result notifies listeners as the background isolate scans more pages.
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }
    if (trimmed == _query && _result != null) return;

    _clearResult();
    _query       = trimmed;
    _isSearching = true;
    _notifier.notify();

    // Synchronous — returns immediately with a live result object.
    final result = _sfController.searchText(
      trimmed,
      searchOption: sfpdf.TextSearchOption.caseSensitive,
    );

    _result      = result;
    _isSearching = false;

    // Listen for incremental totalInstanceCount updates and next/prev changes.
    _result!.addListener(_onResultChanged);
    _notifier.notify();
  }

  /// Navigates to the next search result.
  void nextResult() {
    if (_result == null || totalCount == 0) return;
    _result!.nextInstance();
    // _onResultChanged fires → _notifier.notify() propagates the index update.
  }

  /// Navigates to the previous search result.
  void previousResult() {
    if (_result == null || totalCount == 0) return;
    _result!.previousInstance();
  }

  /// Clears the active search and removes all Syncfusion highlights.
  void clearSearch() {
    _clearResult();
    _query       = '';
    _isSearching = false;
    _notifier.notify();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _clearResult() {
    if (_result != null) {
      _result!.removeListener(_onResultChanged);
      _result!.clear();
      _result = null;
    }
  }

  void _onResultChanged() {
    // Fires on every incremental scan update and on next/prev navigation.
    _notifier.notify();
  }

  void dispose() {
    _clearResult();
    _notifier.dispose();
  }
}