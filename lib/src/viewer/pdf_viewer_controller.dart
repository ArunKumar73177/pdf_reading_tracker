import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
/// ## Highlight persistence — how it works (v2.5.0)
///
/// ### Verified Syncfusion 27.x API surface (from pub.dev docs)
/// [sf.HighlightAnnotation] exposes only the properties inherited from
/// [sf.Annotation]: `color`, `opacity`, `pageNumber`, `author`, `subject`,
/// `name`, `isLocked`. It does NOT expose `textMarkupRects`, `bounds`, or
/// any rect accessor. [sf.PdfViewerController.getAnnotations()] returns
/// `List<Annotation>` — same base class only.
///
/// ### Capture (new highlight)
/// 1. User selects text → the viewer state calls [captureTextSelection] with
///    the raw [sf.PdfTextLine] list obtained from
///    `SfPdfViewerState.getSelectedTextLines()`.
/// 2. Host widget calls [commitHighlightFromLines] — we build a [Highlight]
///    from those lines and persist it.  The annotation was already added to
///    Syncfusion by the caller immediately before invoking this method.
///
/// ### Restore (document open)
/// [_loadAndRestoreHighlights] fetches all [Highlight] rows for this PDF,
/// reconstructs each `sf.HighlightAnnotation` from the stored `rectList`,
/// and adds it via `sfController.addAnnotation()`.
///
/// ### Remove
/// Because no rect accessor exists on [sf.Annotation], we match the
/// annotation to remove by page number and insertion order (index within the
/// filtered list), which is sufficient since each restore/add is ordered.
///
/// ### Page number boundary
/// - Stored [Highlight.page]: **zero-based**.
/// - Syncfusion `pageNumber`: **one-based**.
/// - Conversion: `storedPage = sfPageNumber - 1` (inbound).
///               `sfPageNumber = storedPage + 1`  (outbound).
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

  late final PdfSearchController searchController =
  PdfSearchController(sfController: sfController);

  // ---------------------------------------------------------------------------
  // Scoped notifiers
  // ---------------------------------------------------------------------------

  final ChangeNotifier pageNotifier      = ChangeNotifier();
  final ChangeNotifier bookmarksNotifier = ChangeNotifier();
  final ChangeNotifier savingNotifier    = ChangeNotifier();
  final ChangeNotifier highlightNotifier = ChangeNotifier();

  ChangeNotifier get searchNotifier => searchController.notifier;

  // ---------------------------------------------------------------------------
  // Exposed state
  // ---------------------------------------------------------------------------

  bool    _loading = true;
  bool    get isLoading => _loading;

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
  // Pending text selection
  // ---------------------------------------------------------------------------

  /// Non-null while the user has text selected and has not yet tapped
  /// "Highlight".  Cleared by [commitHighlightFromLines] or when selection
  /// is cancelled.
  PendingTextSelection? _pendingSelection;
  PendingTextSelection? get pendingSelection => _pendingSelection;

  // ---------------------------------------------------------------------------
  // Internal flags
  // ---------------------------------------------------------------------------

  bool _hasRendered      = false;
  int? _pendingJumpTarget;
  int  _persistedPage       = -1;
  int  _persistedTotalPages = -1;

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
    _error             = null;
    _hasRendered       = false;
    _pendingJumpTarget = null;
    _pendingSelection  = null;

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
        _applyProgress(results[1] as ReadingProgress);
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
        _applyProgress(results[1] as ReadingProgress);
      }
    } catch (e, st) {
      debugPrintStack(stackTrace: st, label: 'PdfViewerController.init');
      _error = 'Failed to load PDF: $e';
    } finally {
      _setLoading(false);
    }
  }

  void _applyProgress(ReadingProgress saved) {
    _initialPage = saved.currentPage;
    _currentPage = saved.currentPage;
    _totalPages  = saved.totalPages;
    _log('Restored page $_currentPage / $_totalPages');
  }

  @override
  void dispose() {
    if (_progressDebounce?.isActive == true) {
      _progressDebounce!.cancel();
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
  // Syncfusion document callbacks
  // ---------------------------------------------------------------------------

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

  void onDocumentLoaded(int pageCount) {
    _totalPages = pageCount;
    pageNotifier.notifyListeners();

    if (!_hasRendered) {
      _hasRendered = true;
      _reloadBookmarks();
      _loadAndRestoreHighlights();
      _schedulePersistProgress();
    }
  }

  void onDocumentLoadFailed(String description) {
    _error = 'Failed to load PDF: $description';
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Text selection capture
  // ---------------------------------------------------------------------------

  /// Called from the viewer state when the user selects text.
  ///
  /// [selectedText] is the plain text; [globalRegion] is the screen-space
  /// bounding rect (used for positioning the action bar); [textLines] are
  /// the raw [sf.PdfTextLine] objects from
  /// `SfPdfViewerState.getSelectedTextLines()`.
  ///
  /// When [selectedText] is null/empty the pending selection is cleared.
  void captureTextSelection(
      String? selectedText,
      Rect? globalRegion,
      List<sf.PdfTextLine>? textLines,
      ) {
    if (selectedText == null || selectedText.trim().isEmpty) {
      if (_pendingSelection != null) {
        _pendingSelection = null;
        highlightNotifier.notifyListeners();
      }
      return;
    }
    _pendingSelection = PendingTextSelection(
      selectedText: selectedText,
      globalRegion: globalRegion,
      page:         _currentPage,
      textLines:    textLines ?? const [],
    );
    highlightNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Highlight: commit from captured text lines
  // ---------------------------------------------------------------------------

  /// Called by the viewer after it has added the [sf.HighlightAnnotation] to
  /// Syncfusion.  [textLines] are the `PdfTextLine` objects used to create
  /// that annotation; [colorValue] is the annotation's `color.value`.
  ///
  /// If [textLines] is empty (edge-case: selection cleared before commit),
  /// the call is a no-op.
  Future<void> commitHighlightFromLines({
    required List<sf.PdfTextLine> textLines,
    required int colorValue,
  }) async {
    final pending = _pendingSelection;
    _pendingSelection = null;

    if (textLines.isEmpty) {
      _log('commitHighlightFromLines: empty textLines — skipping');
      highlightNotifier.notifyListeners();
      return;
    }

    // Build HighlightRect list from the PdfTextLine bounds.
    // PdfTextLine.bounds is relative to the PDF page dimensions.
    final rects = textLines
        .map((line) => HighlightRect(
      left:   line.bounds.left,
      top:    line.bounds.top,
      right:  line.bounds.right,
      bottom: line.bounds.bottom,
    ))
        .toList(growable: false);

    // Page is taken from the first text line (one-based → zero-based).
    // Falls back to the page recorded at selection-capture time.
    final zeroPage = textLines.isNotEmpty
        ? textLines.first.pageNumber - 1   // BOUNDARY: one → zero
        : (pending?.page ?? _currentPage);

    final highlight = Highlight.create(
      pdfId:        pdfId,
      page:         zeroPage,
      selectedText: pending?.selectedText ?? textLines.first.text,
      rectList:     rects,
      colorValue:   colorValue,
    );

    try {
      final rowId  = await HighlightService.instance.addHighlight(highlight);
      final stored = highlight.copyWith(id: rowId);
      final updated = List<Highlight>.of(_highlights)..add(stored);
      updated.sort((a, b) => a.page.compareTo(b.page));
      _highlights = updated;
      _log('Highlight saved rowId=$rowId page=$zeroPage rects=${rects.length}');
    } catch (e) {
      _log('Failed to persist highlight (non-fatal): $e');
    }

    highlightNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Highlight: remove
  // ---------------------------------------------------------------------------

  /// Removes the highlight with the given [id] from SQLite and from the
  /// Syncfusion viewer.
  ///
  /// Because [sf.Annotation] exposes only [sf.Annotation.pageNumber] (no
  /// rect accessor), we match by page and remove the annotation at the same
  /// index as the stored highlight appears within the per-page list. This
  /// is reliable as long as highlights are added and removed in order (which
  /// they are — restores happen sequentially on document open).
  Future<void> removeHighlight(int id) async {
    final idx = _highlights.indexWhere((h) => h.id == id);
    if (idx == -1) {
      _log('removeHighlight: id=$id not found in memory list');
      return;
    }

    final stored = _highlights[idx];
    _removeSfAnnotation(stored);

    await HighlightService.instance.removeHighlight(id);

    _highlights = _highlights.where((h) => h.id != id).toList(growable: false);
    _log('Highlight removed id=$id');
    highlightNotifier.notifyListeners();
  }

  /// Finds the Syncfusion [sf.HighlightAnnotation] that corresponds to
  /// [highlight] and removes it via [sfController.removeAnnotation].
  ///
  /// Match strategy: filter `getAnnotations()` to [sf.HighlightAnnotation]
  /// objects on the same (one-based) page, then pick the one at the same
  /// relative index as [highlight] appears among highlights on that page.
  void _removeSfAnnotation(Highlight highlight) {
    final sfPage = highlight.page + 1; // BOUNDARY: zero → one

    // All stored highlights on this page, in list order.
    final pageHighlights = _highlights
        .where((h) => h.page == highlight.page)
        .toList(growable: false);
    final relativeIdx = pageHighlights.indexWhere((h) => h.id == highlight.id);

    // Live Syncfusion annotations on the same page.
    final sfOnPage = sfController
        .getAnnotations()
        .whereType<sf.HighlightAnnotation>()
        .where((a) => a.pageNumber == sfPage)
        .toList(growable: false);

    if (relativeIdx >= 0 && relativeIdx < sfOnPage.length) {
      sfController.removeAnnotation(sfOnPage[relativeIdx]);
      return;
    }

    // Fallback: remove first match on page (avoids leaving orphan annotations).
    if (sfOnPage.isNotEmpty) {
      sfController.removeAnnotation(sfOnPage.first);
      _log('_removeSfAnnotation: used fallback (first on page) for '
          'id=${highlight.id} page=${highlight.page}');
      return;
    }

    _log('_removeSfAnnotation: no Syncfusion annotation found for '
        'id=${highlight.id} page=${highlight.page} — viewer already clean');
  }

  // ---------------------------------------------------------------------------
  // Highlight: load from SQLite and restore to Syncfusion viewer
  // ---------------------------------------------------------------------------

  Future<void> _loadAndRestoreHighlights() async {
    try {
      _highlights = await HighlightService.instance.getHighlights(pdfId);
      _log('Highlights loaded: ${_highlights.length} for pdfId=$pdfId');
    } catch (e) {
      _log('Failed to load highlights (non-fatal): $e');
      _highlights = [];
    }

    // Notify UI immediately so the highlight list renders before Syncfusion
    // finishes adding annotations.
    highlightNotifier.notifyListeners();

    _restoreHighlightsToViewer();
  }

  /// Reconstructs [sf.HighlightAnnotation] objects from stored [_highlights]
  /// and pushes them into the Syncfusion controller.
  void _restoreHighlightsToViewer() {
    for (final highlight in _highlights) {
      try {
        _addHighlightToSfController(highlight);
      } catch (e) {
        _log('Failed to restore highlight id=${highlight.id} '
            'page=${highlight.page}: $e');
      }
    }
    _log('Highlights restored to viewer: ${_highlights.length}');
  }

  /// Builds a [sf.HighlightAnnotation] from a persisted [Highlight] and
  /// calls [sfController.addAnnotation].
  ///
  /// BOUNDARY (outbound): [Highlight.page] is zero-based → add 1 for
  /// [sf.PdfTextLine] which expects a one-based page number.
  void _addHighlightToSfController(Highlight highlight) {
    final sfPageNumber = highlight.page + 1; // zero → one

    final textLines = highlight.rectList.map((r) {
      return sf.PdfTextLine(
        Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
        highlight.selectedText,
        sfPageNumber,
      );
    }).toList(growable: false);

    if (textLines.isEmpty) return;

    final annotation = sf.HighlightAnnotation(
      textBoundsCollection: textLines,
    );
    annotation.color = Color(highlight.colorValue);

    sfController.addAnnotation(annotation);
  }

  // ---------------------------------------------------------------------------
  // Bookmark operations
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
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx != -1) {
      final updated = List<Bookmark>.of(_bookmarks);
      updated[idx]  = updated[idx].copyWith(note: note);
      _bookmarks    = updated;
    }
    bookmarksNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> goToPage(int page) async {
    if (!_hasRendered) return;
    if (page == _currentPage) return;
    _currentPage = page;
    pageNotifier.notifyListeners();
    _pendingJumpTarget = page;
    sfController.jumpToPage(page + 1); // BOUNDARY: zero → one
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<String> _extractAsset() async {
    final dir  = await getTemporaryDirectory();
    final safe = pdfId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safe.pdf');
    if (!file.existsSync()) {
      _log('Extracting $assetPath -> ${file.path}');
      final data = await rootBundle.load(assetPath!);
      await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } else {
      _log('Asset already cached: ${file.path}');
    }
    return file.path;
  }

  void _schedulePersistProgress() {
    if (_currentPage == _persistedPage &&
        _totalPages  == _persistedTotalPages) return;
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

  void _persistProgressImmediate() {
    ProgressService.instance
        .saveProgress(ReadingProgress.create(
      pdfId:       pdfId,
      currentPage: _currentPage,
      totalPages:  _totalPages,
      title:       pdfTitle,
      filePath:    onDeviceFilePath,
    ))
        .catchError((e) => _log('Dispose-time save failed: $e'));
  }

  Future<void> _reloadBookmarks() async {
    _bookmarks = await BookmarkService.instance.getBookmarks(pdfId);
    _log('Bookmarks: ${_bookmarks.length} for pdfId=$pdfId');
    bookmarksNotifier.notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _log(String msg) => debugPrint('[PdfViewerCtrl:$pdfId] $msg');
}

// ---------------------------------------------------------------------------
// PendingTextSelection
// ---------------------------------------------------------------------------

/// Transient capture of a user text selection, held between
/// `onTextSelectionChanged` and the user tapping "Highlight".
///
/// [textLines] carries the raw [sf.PdfTextLine] objects obtained from
/// `SfPdfViewerState.getSelectedTextLines()`.  These are the ground-truth
/// rect data used both to create the [sf.HighlightAnnotation] and to
/// populate [Highlight.rectList] for SQLite persistence.
class PendingTextSelection {
  const PendingTextSelection({
    required this.selectedText,
    required this.globalRegion,
    required this.page,
    required this.textLines,
  });

  final String selectedText;

  /// Global screen-space bounding rect — used only for positioning the
  /// action bar tooltip; may be null on some Syncfusion versions.
  final Rect? globalRegion;

  /// Zero-based page where the selection was made.
  final int page;

  /// Raw Syncfusion text lines captured from
  /// `SfPdfViewerState.getSelectedTextLines()` at selection time.
  ///
  /// These are passed directly to [PdfViewerController.commitHighlightFromLines]
  /// and into [sf.HighlightAnnotation]'s `textBoundsCollection` constructor.
  final List<sf.PdfTextLine> textLines;
}