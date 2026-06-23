import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

// ---------------------------------------------------------------------------
// Internal notifier
// ---------------------------------------------------------------------------

class _PublicNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Encapsulates all PDF text-search state and drives Syncfusion's native
/// search mechanism via [sf.PdfViewerController].
///
/// ### Case-insensitive search — how it works
///
/// `SfPdfViewer.searchText()` delegates internally to
/// `PdfTextExtractor.findText()`. When `searchOption` is **null** (omitted),
/// the extractor uses `pageText.toLowerCase().contains(term.toLowerCase())`
/// — i.e. plain case-insensitive substring matching.
///
/// The available `TextSearchOption` values in Syncfusion 27.x are:
///
/// | Value                            | Behaviour                            |
/// |----------------------------------|--------------------------------------|
/// | `null` (omitted) ← **we use this** | Case-insensitive substring match  |
/// | `TextSearchOption.caseSensitive` | Exact-case match only                |
/// | `TextSearchOption.wholeWords`    | Whole words, case-insensitive        |
/// | `TextSearchOption.both`          | Whole words + case-sensitive         |
///
/// `TextSearchOption.none` does **not** exist in 27.x and must never be used.
///
/// ### Previous bug
///
/// An earlier version imported `syncfusion_flutter_pdf` and passed
/// `sfpdf.TextSearchOption.none` — a value that does not exist in the enum,
/// causing a compile error. The fix is to omit `searchOption` entirely,
/// which is both the correct and the simplest solution.
class PdfSearchController {
  PdfSearchController({required sf.PdfViewerController sfController})
      : _sfController = sfController;

  final sf.PdfViewerController _sfController;

  // ---------------------------------------------------------------------------
  // Notifier
  // ---------------------------------------------------------------------------

  final _PublicNotifier _notifier = _PublicNotifier();

  /// Listen to this to rebuild search-related UI only.
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

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  bool get hasActiveSearch => _query.isNotEmpty;

  /// Total matches found so far (grows incrementally as Syncfusion scans).
  int get totalCount => _result?.totalInstanceCount ?? 0;

  /// 1-based index of the currently highlighted match.
  int get currentIndex => _result?.currentInstanceIndex ?? 0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initiates a case-insensitive search for [query].
  ///
  /// Passing no `searchOption` (null) to [sf.PdfViewerController.searchText]
  /// triggers the case-insensitive substring path inside Syncfusion's
  /// `PdfTextExtractor`. This means "flutter", "Flutter", "FLUTTER", and
  /// "ArChItEcTuRe" all produce identical result sets.
  ///
  /// Do **not** pass `TextSearchOption.caseSensitive` (exact case only) or
  /// the non-existent `TextSearchOption.none` (compile error).
  void search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearSearch();
      return;
    }
    if (trimmed == _query && _result != null) return;

    _clearResult();
    _query = trimmed;
    _isSearching = true;
    _notifier.notify();

    // Omitting searchOption (null) = case-insensitive substring search.
    // This is the correct, version-safe approach for Syncfusion 27.x.
    final result = _sfController.searchText(trimmed);

    _result = result;
    _isSearching = false;

    _result!.addListener(_onResultChanged);
    _notifier.notify();
  }

  /// Navigates to the next search result.
  void nextResult() {
    if (_result == null || totalCount == 0) return;
    _result!.nextInstance();
  }

  /// Navigates to the previous search result.
  void previousResult() {
    if (_result == null || totalCount == 0) return;
    _result!.previousInstance();
  }

  /// Clears the active search and removes all Syncfusion highlights.
  void clearSearch() {
    _clearResult();
    _query = '';
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
    _notifier.notify();
  }

  void dispose() {
    _clearResult();
    _notifier.dispose();
  }
}