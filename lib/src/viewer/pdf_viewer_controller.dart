import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/reading_progress.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/progress_service.dart';
import 'pdf_search_controller.dart';

/// Source of truth for [PdfReadingTrackerViewer].
///
/// ## Architecture (v2.3.0 → v2.4.0)
///
/// ### Page-number convention
/// Every page number exposed through the public surface (`currentPage`,
/// `initialPage`, `totalPages`, [Bookmark.page], [Highlight.page]) is
/// **zero-based**, exactly as SQLite has always expected.
/// Syncfusion's controller and callbacks are **one-based**. Conversions
/// happen at exactly two narrow boundaries:
///   - Inbound:  Syncfusion page → subtract 1 → stored in `_currentPage`.
///   - Outbound: `goToPage(zeroPage)` → add 1 → passed to `jumpToPage`.
///
/// ### Scoped notifiers (Fix 2 — preserved)
/// | Notifier            | Fires on                                         |
/// |---------------------|--------------------------------------------------|
/// | [pageNotifier]      | currentPage / totalPages / progressPct           |
/// | [bookmarksNotifier] | bookmark list CRUD                               |
/// | [savingNotifier]    | debounced-autosave-in-flight flag                |
/// | [searchNotifier]    | search state (query, results, current match)     |
/// | [highlightNotifier] | highlight CRUD                                   |
///
/// ### Performance fixes (v2.4.0)
/// 1. **Dropped-write fix** — `_persistProgress` is now called immediately on
///    `dispose()` (cancelling any in-flight debounce) so the last page is
///    always committed even when the user swipes away quickly.
/// 2. **Debounce gate** — `_schedulePersistProgress` skips scheduling when
///    the value has not changed since the last persisted snapshot, avoiding
///    redundant SQLite round-trips on repeated `onPageChanged` fires for the
///    same page (Syncfusion can fire the callback multiple times per swipe).
/// 3. **Search integration** — [PdfSearchController] is wired into
///    `sfController` so text search drives Syncfusion's native highlight
///    mechanism with zero extra paint overhead.
/// 4. **Highlight persistence** — SQLite-backed [HighlightService] stores
///    user selections.  Highlights are loaded once after document render and
///    kept in memory; CRUD operations patch the in-memory list (same pattern
///    as bookmarks Fix 3).
class PdfViewerController extends ChangeNotifier {
  PdfViewerController({
    required this.pdfId,
    required this.pdfTitle,
    this.assetPath,
    this.filePath,
    this.onDeviceFilePath,
  }) : assert(
  (assetPath != null) != (filePath != null),
  'Provide exactly one of assetPath or filePath.',
  );

  final String pdfId;
  final String pdfTitle;
  final String? assetPath;
  final String? filePath;
  final String? onDeviceFilePath;

  // ---------------------------------------------------------------------------
  // Syncfusion controllers
  // ---------------------------------------------------------------------------

  final sf.PdfViewerController sfController = sf.PdfViewerController();

  /// Exposed so [PdfReadingTrackerViewer] can pass it to [_PdfViewerCore]
  /// and to the search UI widgets.
  late final PdfSearchController searchController =
  PdfSearchController(sfController: sfController);

  // ---------------------------------------------------------------------------
  // Scoped notifiers
  // ---------------------------------------------------------------------------

  final ChangeNotifier pageNotifier      = ChangeNotifier();
  final ChangeNotifier bookmarksNotifier = ChangeNotifier();
  final ChangeNotifier savingNotifier    = ChangeNotifier();

  /// Notifies when search state changes (delegates to [PdfSearchController]'s
  /// internal notifier — exposed here so host widgets can listen to a single
  /// source without importing the search controller directly).
  ChangeNotifier get searchNotifier => searchController.notifier;

  /// Notifies when the highlight list changes (add / remove / clear).
  final ChangeNotifier highlightNotifier = ChangeNotifier();

  // ---------------------------------------------------------------------------
  // Exposed state
  // ---------------------------------------------------------------------------

  bool   _loading = true;
  bool   get isLoading => _loading;

  String? _error;
  String? get error => _error;

  String? _resolvedFilePath;
  String? get resolvedFilePath => _resolvedFilePath;

  int _initialPage = 0;
  int get initialPage => _initialPage;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  int _totalPages = 0;
  int get totalPages => _totalPages;

  double get progressPct {
    if (_totalPages <= 0) return 0.0;
    return ((_currentPage + 1) / _totalPages * 100.0).clamp(0.0, 100.0);
  }

  List<Bookmark>  _bookmarks  = [];
  List<Bookmark>  get bookmarks  => List.unmodifiable(_bookmarks);

  List<Highlight> _highlights = [];
  List<Highlight> get highlights => List.unmodifiable(_highlights);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // ---------------------------------------------------------------------------
  // Internal flags
  // ---------------------------------------------------------------------------

  bool _hasRendered      = false;
  int? _pendingJumpTarget;

  /// Last page/totalPages snapshot that was actually written to SQLite.
  /// Used by the debounce gate (Fix 2) to skip redundant writes.
  int _persistedPage       = -1;
  int _persistedTotalPages = -1;

  // ---------------------------------------------------------------------------
  // Debounce
  // ---------------------------------------------------------------------------

  Timer? _progressDebounce;
  static const _kProgressDebounce = Duration(milliseconds: 400);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _log('init() pdfId=$pdfId');
    _setLoading(true);
    _error        = null;
    _hasRendered  = false;
    _pendingJumpTarget = null;

    try {
      if (filePath != null) {
        final results = await Future.wait([
          Future.value(filePath!),
          ProgressService.instance.getOrCreate(
            pdfId: pdfId,
            pdfTitle: pdfTitle,
            onDeviceFilePath: onDeviceFilePath,
          ),
        ]);
        _resolvedFilePath = results[0] as String;
        final saved = results[1] as ReadingProgress;
        _applyProgress(saved);
      } else {
        final results = await Future.wait([
          _extractAsset(),
          ProgressService.instance.getOrCreate(
            pdfId: pdfId,
            pdfTitle: pdfTitle,
            onDeviceFilePath: onDeviceFilePath,
          ),
        ]);
        _resolvedFilePath = results[0] as String;
        final saved = results[1] as ReadingProgress;
        _applyProgress(saved);
      }
    } catch (e, st) {
      debugPrintStack(stackTrace: st, label: 'PdfViewerController.init');
      _error = 'Failed to load PDF: $e';
    } finally {
      _setLoading(false);
    }
  }

  void _applyProgress(ReadingProgress saved) {
    _initialPage  = saved.currentPage;
    _currentPage  = saved.currentPage;
    _totalPages   = saved.totalPages;
    _log('Restored page $_currentPage / $_totalPages');
  }

  @override
  void dispose() {
    // Fix 1 — Dropped-write fix: flush any pending debounced write synchronously.
    if (_progressDebounce?.isActive == true) {
      _progressDebounce!.cancel();
      // Fire-and-forget; dispose must be synchronous.
      _persistProgressImmediate();
    }
    _progressDebounce?.cancel();
    searchController.dispose();
    pageNotifier.dispose();
    bookmarksNotifier.dispose();
    savingNotifier.dispose();
    highlightNotifier.dispose();
    sfController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Syncfusion callbacks
  // ---------------------------------------------------------------------------

  /// Called by `SfPdfViewer.onPageChanged`.
  ///
  /// CONVERSION BOUNDARY: [newPageNumber] is one-based (Syncfusion).
  /// Converted to zero-based here, at the single point of entry.
  void onPageChanged(int newPageNumber) {
    final zeroBasedPage = newPageNumber - 1;
    _currentPage = zeroBasedPage;

    if (_pendingJumpTarget != null) {
      if (zeroBasedPage != _pendingJumpTarget) return;
      _pendingJumpTarget = null;
    }

    pageNotifier.notifyListeners();
    _schedulePersistProgress();
  }

  /// Called by `SfPdfViewer.onDocumentLoaded`.
  void onDocumentLoaded(int pageCount) {
    _totalPages = pageCount;
    pageNotifier.notifyListeners();

    if (!_hasRendered) {
      _hasRendered = true;
      // Parallel load — neither blocks the other.
      _reloadBookmarks();
      _reloadHighlights();
      _schedulePersistProgress();
    }
  }

  /// Called by `SfPdfViewer.onDocumentLoadFailed`.
  void onDocumentLoadFailed(String description) {
    _error = 'Failed to load PDF: $description';
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Bookmark operations (Fix 3 — in-memory patch, no full re-read)
  // ---------------------------------------------------------------------------

  Future<void> addBookmark({String? note}) async {
    if (_bookmarks.any((b) => b.page == _currentPage)) {
      _log('Page $_currentPage already bookmarked');
      return;
    }
    final bm    = Bookmark.create(pdfId: pdfId, page: _currentPage, note: note);
    final rowId = await BookmarkService.instance.addBookmark(bm);
    _log('Bookmark added rowId=$rowId page=$_currentPage');

    final stored  = bm.copyWith(id: rowId);
    final updated = List<Bookmark>.of(_bookmarks)..add(stored);
    updated.sort((a, b) => a.page.compareTo(b.page));
    _bookmarks = updated;
    bookmarksNotifier.notifyListeners();
  }

  Future<void> removeBookmark(int id) async {
    await BookmarkService.instance.removeBookmark(id);
    _log('Bookmark removed id=$id');
    _bookmarks = _bookmarks.where((b) => b.id != id).toList(growable: false);
    bookmarksNotifier.notifyListeners();
  }

  Future<void> updateBookmarkNote(int id, String? note) async {
    await BookmarkService.instance.updateNote(id, note);
    _log('Bookmark note updated id=$id');
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx != -1) {
      final updated = List<Bookmark>.of(_bookmarks);
      updated[idx]  = updated[idx].copyWith(note: note);
      _bookmarks    = updated;
    }
    bookmarksNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Highlight operations
  // ---------------------------------------------------------------------------

  /// Persists [highlight] and patches the in-memory list.
  Future<void> addHighlight(Highlight highlight) async {
    final rowId   = await HighlightService.instance.addHighlight(highlight);
    final stored  = highlight.copyWith(id: rowId);
    final updated = List<Highlight>.of(_highlights)..add(stored);
    updated.sort((a, b) => a.page.compareTo(b.page));
    _highlights = updated;
    _log('Highlight added rowId=$rowId page=${highlight.page}');
    highlightNotifier.notifyListeners();
  }

  Future<void> removeHighlight(int id) async {
    await HighlightService.instance.removeHighlight(id);
    _highlights = _highlights.where((h) => h.id != id).toList(growable: false);
    _log('Highlight removed id=$id');
    highlightNotifier.notifyListeners();
  }

  Future<void> clearHighlightsOnPage(int page) async {
    await HighlightService.instance.clearHighlightsOnPage(pdfId, page);
    _highlights = _highlights.where((h) => h.page != page).toList(growable: false);
    highlightNotifier.notifyListeners();
  }

  /// Returns all highlights on [page] (zero-based).
  List<Highlight> highlightsOnPage(int page) =>
      _highlights.where((h) => h.page == page).toList(growable: false);

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Navigates to the given **zero-based** [page].
  ///
  /// No-op if [page] equals [currentPage] or the document is not yet loaded.
  ///
  /// CONVERSION BOUNDARY: [page] is zero-based on entry;
  /// converted to one-based before calling `jumpToPage`.
  Future<void> goToPage(int page) async {
    if (!_hasRendered) return;
    if (page == _currentPage) return;

    _currentPage = page;
    pageNotifier.notifyListeners();

    _pendingJumpTarget = page;
    sfController.jumpToPage(page + 1); // Syncfusion boundary: +1
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<String> _extractAsset() async {
    final dir  = await getTemporaryDirectory();
    final safe = pdfId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safe.pdf');
    if (!file.existsSync()) {
      _log('Extracting $assetPath → ${file.path}');
      final data = await rootBundle.load(assetPath!);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } else {
      _log('Asset already cached: ${file.path}');
    }
    return file.path;
  }

  /// Fix 2 — Debounce gate: skips rescheduling when page+totalPages have not
  /// changed since the last successful SQLite write.  Syncfusion can fire
  /// `onPageChanged` multiple times for the same logical page during a fling;
  /// this gate collapses those into a single write.
  void _schedulePersistProgress() {
    if (_currentPage == _persistedPage && _totalPages == _persistedTotalPages) {
      return;
    }
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_kProgressDebounce, _persistProgress);
  }

  Future<void> _persistProgress() async {
    if (_savingProgress) return;
    _savingProgress = true;
    savingNotifier.notifyListeners();
    try {
      await ProgressService.instance.saveProgress(
        ReadingProgress.create(
          pdfId:       pdfId,
          currentPage: _currentPage,
          totalPages:  _totalPages,
          title:       pdfTitle,
          filePath:    onDeviceFilePath,
        ),
      );
      _persistedPage       = _currentPage;
      _persistedTotalPages = _totalPages;
    } catch (e) {
      _log('Progress save failed (non-fatal): $e');
    } finally {
      _savingProgress = false;
      savingNotifier.notifyListeners();
    }
  }

  /// Fire-and-forget variant used from [dispose] so the last page is never
  /// dropped when the user leaves quickly.  Does not touch [_savingProgress]
  /// (the widget tree is already tearing down).
  void _persistProgressImmediate() {
    ProgressService.instance
        .saveProgress(
      ReadingProgress.create(
        pdfId:       pdfId,
        currentPage: _currentPage,
        totalPages:  _totalPages,
        title:       pdfTitle,
        filePath:    onDeviceFilePath,
      ),
    )
        .catchError((e) => _log('Dispose-time save failed (non-fatal): $e'));
  }

  Future<void> _reloadBookmarks() async {
    _bookmarks = await BookmarkService.instance.getBookmarks(pdfId);
    _log('Bookmarks: ${_bookmarks.length} for pdfId=$pdfId');
    bookmarksNotifier.notifyListeners();
  }

  Future<void> _reloadHighlights() async {
    _highlights = await HighlightService.instance.getHighlights(pdfId);
    _log('Highlights: ${_highlights.length} for pdfId=$pdfId');
    highlightNotifier.notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _log(String msg) => debugPrint('[PdfViewerCtrl:$pdfId] $msg');
}