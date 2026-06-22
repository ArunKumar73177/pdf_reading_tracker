import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/note.dart';
import '../models/reading_progress.dart';
import '../services/bookmark_service.dart';
import '../services/highlight_service.dart';
import '../services/note_service.dart';
import '../services/progress_service.dart';
import 'pdf_search_controller.dart';
import 'widgets/annotation_action_bar.dart';

// ---------------------------------------------------------------------------
// Note annotation color
// ---------------------------------------------------------------------------

/// ARGB color used for the in-PDF highlight that marks text with an attached
/// note. Distinct from all user-selectable annotation colors.
///
/// Teal at 55 % opacity.
const int _kNoteAnnotationColor = 0x8C00BCD4;

// ---------------------------------------------------------------------------
// PdfViewerController
// ---------------------------------------------------------------------------

/// Source of truth for [PdfReadingTrackerViewer].
///
/// ---
/// ## Issue 1 fix — text-anchor snapshot for notes
///
/// ### Problem
/// When the user selects text and then taps the "Add Note" FAB,
/// `SfPdfViewer` fires `onTextSelectionChanged(null, null)` the moment the
/// FAB receives focus (touch-up lands outside the viewer). This clears
/// `_pendingSelection` before `_handleAddNoteTap` reads it, so every note
/// is saved with `selectedText=''` and an empty `rectList`.
///
/// ### Fix
/// A **snapshot** of the pending selection (`_selectionSnapshot`) is taken
/// every time `captureTextSelection` receives a non-empty selection and
/// stored in a separate field. The snapshot is cleared only when the user
/// explicitly commits or dismisses the annotation bar, or when a new note
/// is saved — not when the viewer fires a deselection event.
///
/// `_handleAddNoteTap` in the viewer reads `snapshotSelection` (not
/// `pendingSelection`) so it always gets the last intentional selection.
///
/// ---
/// ## Issue 3 fix — scroll-extent-based page detection
///
/// ### Problem
/// The previous implementation called `sfController.getPageOffset(n)` which
/// does NOT exist in `syncfusion_flutter_pdfviewer` 27.x. An `extension`
/// stub silently replaced it with a no-op returning null, so the midpoint
/// algorithm never ran and page detection fell back to
/// `sfController.pageNumber` (top-edge heuristic).
///
/// ### Fix
/// `onScrollUpdate` now takes a [ScrollMetrics] argument (passed from the
/// `NotificationListener` in `_PdfViewerCore`). From `ScrollMetrics`:
///
/// - `pixels`          — current scroll offset (same as the old `scrollOffset.dy`)
/// - `maxScrollExtent` — total scrollable height of the document
///
/// Assuming all pages have equal height (Syncfusion continuous-scroll
/// renders each page at the same zoom level, so equal height is true at any
/// given zoom), the position of page N's top edge is:
///
///   `pageTop(n) = (n - 1) * pageHeight`   where n is 1-based
///   `pageHeight = maxScrollExtent / (totalPages - 1)`   (last page top = maxScrollExtent)
///
/// If `totalPages == 1`, we are always on page 1.
///
/// The dominant page is the one where `pixels` falls between `pageTop(n)`
/// and `pageTop(n+1)`. Among the two candidates (current and next),
/// the dominant page is the one whose top is closest to the *midpoint* of
/// the visible viewport. Because we do not know viewport height from
/// `ScrollMetrics` alone (it is `viewportDimension`), the simpler and
/// equally correct criterion is:
///
///   if `pixels >= (pageTop(candidate) + pageTop(candidate+1)) / 2`
///       → next page is dominant
///
/// This is mathematically identical to: next page occupies > 50 % of the
/// viewport top half, which is the desired UX.
///
/// ### Syncfusion APIs used (documented in 27.x)
/// - `PdfViewerController.pageNumber`   → int (1-based, top-edge)
/// - `PdfViewerController.jumpToPage()` → void
/// - `PdfViewerController.addAnnotation()`
/// - `PdfViewerController.removeAnnotation()`
/// - `PdfViewerController.getAnnotations()`
/// - `PdfViewerController.clearSelection()`
/// - `PdfViewerController.searchText()`
/// - `ScrollMetrics.pixels`             → double
/// - `ScrollMetrics.maxScrollExtent`    → double
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

  // -------------------------------------------------------------------------
  // Syncfusion controllers
  // -------------------------------------------------------------------------

  final sf.PdfViewerController sfController = sf.PdfViewerController();

  late final PdfSearchController searchController =
  PdfSearchController(sfController: sfController);

  // -------------------------------------------------------------------------
  // Scoped notifiers
  // -------------------------------------------------------------------------

  final ChangeNotifier pageNotifier = ChangeNotifier();
  final ChangeNotifier bookmarksNotifier = ChangeNotifier();
  final ChangeNotifier savingNotifier = ChangeNotifier();
  final ChangeNotifier highlightNotifier = ChangeNotifier();
  final ChangeNotifier notesNotifier = ChangeNotifier();

  ChangeNotifier get searchNotifier => searchController.notifier;

  // -------------------------------------------------------------------------
  // Disposal guard
  // -------------------------------------------------------------------------

  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Exposed state
  // -------------------------------------------------------------------------

  bool _loading = true;
  bool get isLoading => _loading;

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

  double _progressPct = 0.0;

  double get progressPct => _progressPct;

  /// Recomputes and caches [progressPct]. Call whenever [_currentPage] or
  /// [_totalPages] changes.
  void _updateProgressPct() {
    _progressPct = _totalPages <= 0
        ? 0.0
        : ((_currentPage + 1) / _totalPages * 100.0).clamp(0.0, 100.0);
  }

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  List<Highlight> _highlights = [];
  List<Highlight> get highlights => List.unmodifiable(_highlights);

  List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // -------------------------------------------------------------------------
  // Note count cache
  // -------------------------------------------------------------------------

  int _noteCountCachedPage = -1;
  int _noteCountOnCurrentPage = 0;

  /// Number of notes whose [Note.page] matches [currentPage]. O(1) read.
  int get noteCountOnCurrentPage => _noteCountOnCurrentPage;

  void _updateNoteCountCache() {
    // Early exit: re-scan only when the page actually changes.
    if (_noteCountCachedPage == _currentPage) return;
    _noteCountCachedPage = _currentPage;
    _noteCountOnCurrentPage =
        _notes.where((n) => n.page == _currentPage).length;
  }

  /// Invalidates the note count cache (call after notes list mutates).
  void _invalidateNoteCountCache() {
    _noteCountCachedPage = -1;
    _updateNoteCountCache();
  }

  // -------------------------------------------------------------------------
  // Text selection — live pending + stable snapshot
  //
  // _pendingSelection  : live, cleared whenever SfPdfViewer fires a
  //                      deselection event (onTextSelectionChanged(null)).
  //                      Drives the AnnotationActionBar visibility.
  //
  // _selectionSnapshot : stable, set whenever a non-empty selection is
  //                      captured; cleared only when the user explicitly
  //                      commits or dismisses the bar, or after a note is
  //                      saved. Never cleared by a viewer deselection event.
  //                      Read by _handleAddNoteTap via snapshotSelection.
  // -------------------------------------------------------------------------

  PendingTextSelection? _pendingSelection;
  PendingTextSelection? get pendingSelection => _pendingSelection;

  PendingTextSelection? _selectionSnapshot;

  /// The most-recent intentional text selection. Survives the viewer's
  /// deselection event that fires when the user taps the note FAB.
  ///
  /// The viewer reads this in `_handleAddNoteTap` instead of
  /// `pendingSelection`.
  PendingTextSelection? get snapshotSelection => _selectionSnapshot;

  /// Clears the snapshot after the note dialog has consumed it.
  void clearSnapshot() {
    _selectionSnapshot = null;
  }

  // -------------------------------------------------------------------------
  // Internal flags
  // -------------------------------------------------------------------------

  bool _hasRendered = false;
  int? _pendingJumpTarget;
  int _persistedPage = -1;
  int _persistedTotalPages = -1;

  // -------------------------------------------------------------------------
  // Scroll-extent page detection
  // -------------------------------------------------------------------------

  /// Updated on every [ScrollUpdateNotification] from [onScrollUpdate].
  /// Used to compute page height for the midpoint algorithm.
  double _lastMaxScrollExtent = 0.0;

  // -------------------------------------------------------------------------
  // Debounce
  // -------------------------------------------------------------------------

  Timer? _progressDebounce;
  static const _kProgressDebounce = Duration(milliseconds: 400);

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> init() async {
    _log('init() pdfId=$pdfId');
    _setLoading(true);
    _error = null;
    _hasRendered = false;
    _pendingJumpTarget = null;
    _pendingSelection = null;
    _selectionSnapshot = null;

    try {
      if (filePath != null) {
        final results = await Future.wait<Object>([
          Future<Object>.value(filePath!),
          ProgressService.instance.getOrCreate(
            pdfId: pdfId,
            pdfTitle: pdfTitle,
            onDeviceFilePath: onDeviceFilePath,
          ),
        ]);
        if (_disposed) return;
        _resolvedFilePath = results[0] as String;
        _applyProgress(results[1] as ReadingProgress);
      } else {
        final results = await Future.wait<Object>([
          _extractAsset(),
          ProgressService.instance.getOrCreate(
            pdfId: pdfId,
            pdfTitle: pdfTitle,
            onDeviceFilePath: onDeviceFilePath,
          ),
        ]);
        if (_disposed) return;
        _resolvedFilePath = results[0] as String;
        _applyProgress(results[1] as ReadingProgress);
      }
    } catch (e, st) {
      if (_disposed) return;
      debugPrintStack(stackTrace: st, label: 'PdfViewerController.init');
      _error = 'Failed to load PDF: $e';
    } finally {
      _setLoading(false);
    }
  }

  void _applyProgress(ReadingProgress saved) {
    _initialPage = saved.currentPage;
    _currentPage = saved.currentPage;
    _totalPages = saved.totalPages;
    _updateProgressPct();
    _log('Restored page $_currentPage / $_totalPages');
  }

  @override
  void dispose() {
    _disposed = true;
    if (_progressDebounce?.isActive == true) {
      _progressDebounce!.cancel();
      _persistProgressImmediate();
    }
    // Note: _progressDebounce is already cancelled above; no second cancel needed.
    searchController.dispose();
    pageNotifier.dispose();
    bookmarksNotifier.dispose();
    savingNotifier.dispose();
    highlightNotifier.dispose();
    notesNotifier.dispose();
    sfController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Syncfusion document callbacks
  // -------------------------------------------------------------------------

  /// Fallback page update from Syncfusion's `onPageChanged`. Used when the
  /// scroll-based detection has not yet fired (e.g. initial load or after a
  /// programmatic jump). The `_updateCurrentPage` guard prevents double
  /// notifications if scroll detection already updated the page.
  void onPageChanged(int newPageNumber) {
    if (_disposed) return;
    _updateCurrentPage(newPageNumber - 1, source: 'onPageChanged');
  }

  /// Called by [NotificationListener<ScrollUpdateNotification>] in the viewer.
  ///
  /// ### Scroll-extent-based page detection algorithm
  ///
  /// Uses the viewport center (pixels + viewportDimension/2) to determine
  /// which page occupies the largest fraction of visible area.
  ///
  /// Let:
  ///   `H = maxScrollExtent / max(totalPages - 1, 1)` — estimated height per
  ///        page (equal-height approximation; best available without page-level
  ///        layout data from Syncfusion).
  ///
  ///   `viewportCenter = pixels + viewportDimension / 2`
  ///
  ///   `pageTop(n) = (n - 1) * H`   where n is 1-based.
  ///
  /// The dominant page is the one whose top is closest to (but below)
  /// `viewportCenter`.
  ///
  ///   `dominant = floor(viewportCenter / H) + 1`   clamped to [1, totalPages].
  ///
  /// This is more accurate than comparing `pixels` against a midpoint because
  /// it uses the actual screen center, not just the scroll offset.
  void onScrollUpdate(ScrollMetrics metrics) {
    if (_disposed) return;
    if (!_hasRendered) return;
    if (_totalPages <= 0) return;

    _lastMaxScrollExtent = metrics.maxScrollExtent;

    if (_totalPages == 1) {
      _updateCurrentPage(0, source: 'onScrollUpdate');
      return;
    }

    if (_lastMaxScrollExtent <= 0) {
      // Document not yet fully laid out — fall back to Syncfusion's heuristic.
      final candidate = sfController.pageNumber;
      if (candidate >= 1) {
        _updateCurrentPage(candidate - 1, source: 'onScrollUpdate:fallback');
      }
      return;
    }

    // Estimated page height (equal-height assumption).
    final pageH = _lastMaxScrollExtent / (_totalPages - 1).toDouble();

    // Use the viewport center so the dominant page is the one most visible.
    final viewportCenter =
        metrics.pixels + (metrics.viewportDimension / 2.0);

    // 1-based dominant page.
    final dominant =
        (viewportCenter / pageH).floor().clamp(0, _totalPages - 1) + 1;

    if (dominant != _currentPage + 1) {
      _log('[PAGE_DETECT] '
          'pixels=${metrics.pixels.toStringAsFixed(1)} '
          'vpH=${metrics.viewportDimension.toStringAsFixed(1)} '
          'center=${viewportCenter.toStringAsFixed(1)} '
          'pH=${pageH.toStringAsFixed(1)} '
          'dominant=$dominant');
    }

    _updateCurrentPage(dominant - 1, source: 'onScrollUpdate');
  }

  /// Unified page-update path.
  void _updateCurrentPage(int zeroBasedPage,
      {required String source}) {
    // While a programmatic jump is in flight, only accept the exact target
    // page — but do NOT swallow other pages indefinitely. The guard is
    // cleared as soon as the target arrives.
    if (_pendingJumpTarget != null && zeroBasedPage != _pendingJumpTarget) {
      return;
    }
    _pendingJumpTarget = null; // clear regardless of match
    if (zeroBasedPage == _currentPage) return;
    _currentPage = zeroBasedPage;
    _updateProgressPct();
    _updateNoteCountCache();
    _log('[CURRENT_PAGE] page=${_currentPage + 1} '
        'progress=${progressPct.toStringAsFixed(0)}% '
        'source=$source '
        '[PROGRESS_SAVE=scheduled]');
    pageNotifier.notifyListeners();
    _schedulePersistProgress();
  }

  void onDocumentLoaded(int pageCount) {
    if (_disposed) return;
    _totalPages = pageCount;
    _updateProgressPct();
    _updateNoteCountCache();
    pageNotifier.notifyListeners();

    if (!_hasRendered) {
      _hasRendered = true;
      // Sequential restores avoid concurrent sfController.addAnnotation() calls
      // that can corrupt the annotation list when both async chains resolve in
      // the same event-loop turn.
      _reloadBookmarks().then((_) {
        if (_disposed) return;
        _reloadNotesAndRestoreAnnotations().then((_) {
          if (_disposed) return;
          _loadAndRestoreHighlights();
        });
      });
      _schedulePersistProgress();
    }
  }

  void onDocumentLoadFailed(String description) {
    if (_disposed) return;
    _error = 'Failed to load PDF: $description';
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Text selection capture
  // -------------------------------------------------------------------------

  /// Called whenever Syncfusion fires `onTextSelectionChanged`.
  ///
  /// When [selectedText] is non-empty:
  ///   - Updates `_pendingSelection` (drives the action bar).
  ///   - Updates `_selectionSnapshot` (survives subsequent deselect events).
  ///
  /// When [selectedText] is null/empty:
  ///   - Clears `_pendingSelection` only.
  ///   - Does NOT touch `_selectionSnapshot` — the snapshot is preserved so
  ///     the note FAB can read it even after the viewer fires a deselect.
  void captureTextSelection(
      String? selectedText,
      Rect? globalRegion,
      List<sf.PdfTextLine>? textLines,
      ) {
    if (_disposed) return;

    if (selectedText == null || selectedText.trim().isEmpty) {
      if (_pendingSelection != null) {
        _pendingSelection = null;
        highlightNotifier.notifyListeners();
        // _selectionSnapshot intentionally NOT cleared here.
      }
      return;
    }

    final sel = PendingTextSelection(
      selectedText: selectedText,
      globalRegion: globalRegion,
      page: _currentPage,
      textLines: textLines ?? const [],
    );
    _pendingSelection = sel;
    _selectionSnapshot = sel; // stable copy for note FAB
    highlightNotifier.notifyListeners();
  }

  void clearPdfSelection() {
    try {
      sfController.clearSelection();
    } catch (_) {
      // No active selection or controller not yet attached — safe to ignore.
    }
  }

  // -------------------------------------------------------------------------
  // Annotation: commit (highlight / underline / strikethrough / squiggly)
  // -------------------------------------------------------------------------

  Future<void> commitAnnotation({
    required List<sf.PdfTextLine> textLines,
    required AnnotationCommit commit,
  }) async {
    final pending = _pendingSelection;
    _pendingSelection = null;
    _selectionSnapshot = null; // committed — clear snapshot too

    if (textLines.isEmpty) {
      _log('commitAnnotation: empty textLines — skipping');
      if (!_disposed) highlightNotifier.notifyListeners();
      return;
    }

    final sfAnnotation = _buildSfAnnotation(
      type: commit.type,
      textLines: textLines,
      color: Color(commit.colorValue),
    );
    sfController.addAnnotation(sfAnnotation);

    final rects = textLines
        .map((line) => HighlightRect(
      left: line.bounds.left,
      top: line.bounds.top,
      right: line.bounds.right,
      bottom: line.bounds.bottom,
    ))
        .toList(growable: false);

    final zeroPage = textLines.first.pageNumber - 1;

    final highlight = Highlight.create(
      pdfId: pdfId,
      page: zeroPage,
      selectedText: pending?.selectedText ?? textLines.first.text,
      rectList: rects,
      colorValue: commit.colorValue,
      annotationType: commit.type,
      note: commit.note,
    );

    try {
      final rowId = await HighlightService.instance.addHighlight(highlight);
      if (_disposed) return;
      final stored = highlight.copyWith(id: rowId);
      final updated = List<Highlight>.of(_highlights)..add(stored);
      updated.sort((a, b) => a.page.compareTo(b.page));
      _highlights = updated;
      _log('Annotation saved rowId=$rowId page=$zeroPage '
          'type=${commit.type.dbValue} rects=${rects.length}');
    } catch (e) {
      _log('Failed to persist annotation (non-fatal): $e');
    }

    if (!_disposed) highlightNotifier.notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Annotation: update note on highlight
  // -------------------------------------------------------------------------

  Future<void> updateHighlightNote(int id, String? note) async {
    await HighlightService.instance.updateNote(id, note);
    if (_disposed) return;
    final idx = _highlights.indexWhere((h) => h.id == id);
    if (idx != -1) {
      final updated = List<Highlight>.of(_highlights);
      updated[idx] = updated[idx].copyWith(
        note: note,
        clearNote: note == null,
      );
      _highlights = updated;
    }
    highlightNotifier.notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Annotation: remove highlight
  // -------------------------------------------------------------------------

  Future<void> removeHighlight(int id) async {
    final idx = _highlights.indexWhere((h) => h.id == id);
    if (idx == -1) {
      _log('removeHighlight: id=$id not found in memory list');
      return;
    }
    final stored = _highlights[idx];
    _removeSfHighlightAnnotation(stored);
    await HighlightService.instance.removeHighlight(id);
    if (_disposed) return;
    _highlights =
        _highlights.where((h) => h.id != id).toList(growable: false);
    _log('Annotation removed id=$id');
    highlightNotifier.notifyListeners();
  }

  void _removeSfHighlightAnnotation(Highlight highlight) {
    final sfPage = highlight.page + 1;
    // Single getAnnotations() call — avoid redundant copies per removal.
    final allAnnotations = sfController.getAnnotations();

    final sameTypeOnPage = _highlights
        .where((h) =>
    h.page == highlight.page &&
        h.annotationType == highlight.annotationType)
        .toList(growable: false);
    final relativeIdx =
    sameTypeOnPage.indexWhere((h) => h.id == highlight.id);

    final sfOnPage = _sfAnnotationsOfType(highlight.annotationType, allAnnotations)
        .where((a) => a.pageNumber == sfPage)
        .toList(growable: false);

    if (relativeIdx >= 0 && relativeIdx < sfOnPage.length) {
      sfController.removeAnnotation(sfOnPage[relativeIdx]);
      return;
    }
    if (sfOnPage.isNotEmpty) {
      sfController.removeAnnotation(sfOnPage.first);
      _log('_removeSfHighlightAnnotation: fallback for '
          'id=${highlight.id} page=${highlight.page}');
      return;
    }
    _log('_removeSfHighlightAnnotation: no annotation found for '
        'id=${highlight.id} page=${highlight.page}');
  }

  List<sf.Annotation> _sfAnnotationsOfType(
      AnnotationType type,
      List<sf.Annotation> allAnnotations,
      ) {
    switch (type) {
      case AnnotationType.highlight:
        return allAnnotations.whereType<sf.HighlightAnnotation>().toList();
      case AnnotationType.underline:
        return allAnnotations.whereType<sf.UnderlineAnnotation>().toList();
      case AnnotationType.strikethrough:
        return allAnnotations.whereType<sf.StrikethroughAnnotation>().toList();
      case AnnotationType.squiggly:
        return allAnnotations.whereType<sf.SquigglyAnnotation>().toList();
    }
  }

  // -------------------------------------------------------------------------
  // Highlights: load from SQLite and restore to Syncfusion
  // -------------------------------------------------------------------------

  Future<void> _loadAndRestoreHighlights() async {
    try {
      final loaded = await HighlightService.instance.getHighlights(pdfId);
      if (_disposed) return;
      _highlights = loaded;
      _log('Highlights loaded: ${_highlights.length} for pdfId=$pdfId');
    } catch (e) {
      if (_disposed) return;
      _log('Failed to load highlights (non-fatal): $e');
      _highlights = [];
    }
    if (_disposed) return;
    highlightNotifier.notifyListeners();
    for (final highlight in _highlights) {
      _restoreSingleHighlight(highlight);
    }
    _log('Highlights restored: ${_highlights.length}');
  }

  void _restoreSingleHighlight(Highlight highlight) {
    try {
      if (highlight.rectList.isEmpty) return;
      final textLines = highlight.rectList
          .map((r) => sf.PdfTextLine(
        Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
        highlight.selectedText,
        highlight.page + 1,
      ))
          .toList(growable: false);

      sfController.addAnnotation(
        _buildSfAnnotation(
          type: highlight.annotationType,
          textLines: textLines,
          color: Color(highlight.colorValue),
        ),
      );
    } catch (e) {
      _log('Failed to restore highlight id=${highlight.id}: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Notes: load, restore note annotations, and cache count
  // -------------------------------------------------------------------------

  Future<void> _reloadNotesAndRestoreAnnotations() async {
    try {
      final loaded = await NoteService.instance.getNotes(pdfId);
      if (_disposed) return;
      _notes = loaded;
      _log('Notes loaded: ${_notes.length} for pdfId=$pdfId');
    } catch (e) {
      if (_disposed) return;
      _log('Failed to load notes (non-fatal): $e');
      _notes = [];
    }
    _updateNoteCountCache();
    if (!_disposed) notesNotifier.notifyListeners();
    _restoreAllNoteAnnotations();
  }

  void _restoreAllNoteAnnotations() {
    int restoredCount = 0;
    for (final note in _notes) {
      if (_addNoteAnnotationToViewer(note)) restoredCount++;
    }
    _log('Note annotations restored: $restoredCount');
  }

  /// Adds the teal note-marker annotation to Syncfusion for a single note.
  /// Returns true if an annotation was added, false if skipped.
  bool _addNoteAnnotationToViewer(Note note) {
    if (note.rectList.isEmpty) return false;
    try {
      final textLines = note.rectList
          .map((r) => sf.PdfTextLine(
        Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
        note.selectedText,
        note.page + 1,
      ))
          .toList(growable: false);

      final annotation =
      sf.HighlightAnnotation(textBoundsCollection: textLines);
      annotation.color = const Color(_kNoteAnnotationColor);
      sfController.addAnnotation(annotation);
      return true;
    } catch (e) {
      _log('Failed to add note annotation for note id=${note.id}: $e');
      return false;
    }
  }

  void _removeNoteAnnotationFromViewer(Note note) {
    if (note.rectList.isEmpty) return;
    final sfPage = note.page + 1;
    final noteColor = const Color(_kNoteAnnotationColor);

    // Single getAnnotations() call.
    final allAnnotations = sfController.getAnnotations();
    final tealOnPage = allAnnotations
        .whereType<sf.HighlightAnnotation>()
        .where((a) => a.pageNumber == sfPage && a.color == noteColor)
        .toList(growable: false);

    if (tealOnPage.isEmpty) {
      _log('_removeNoteAnnotationFromViewer: no teal annotation on '
          'page=${note.page} for note id=${note.id}');
      return;
    }

    final anchoredNotesOnPage = _notes
        .where((n) => n.page == note.page && n.rectList.isNotEmpty)
        .toList(growable: false);
    final relativeIdx =
    anchoredNotesOnPage.indexWhere((n) => n.id == note.id);

    if (relativeIdx >= 0 && relativeIdx < tealOnPage.length) {
      sfController.removeAnnotation(tealOnPage[relativeIdx]);
    } else if (tealOnPage.isNotEmpty) {
      sfController.removeAnnotation(tealOnPage.first);
      _log('_removeNoteAnnotationFromViewer: fallback for note id=${note.id}');
    }
  }

  // -------------------------------------------------------------------------
  // Syncfusion annotation builder
  // -------------------------------------------------------------------------

  sf.Annotation _buildSfAnnotation({
    required AnnotationType type,
    required List<sf.PdfTextLine> textLines,
    required Color color,
  }) {
    late sf.Annotation annotation;
    switch (type) {
      case AnnotationType.highlight:
        annotation = sf.HighlightAnnotation(textBoundsCollection: textLines);
      case AnnotationType.underline:
        annotation = sf.UnderlineAnnotation(textBoundsCollection: textLines);
      case AnnotationType.strikethrough:
        annotation =
            sf.StrikethroughAnnotation(textBoundsCollection: textLines);
      case AnnotationType.squiggly:
        annotation = sf.SquigglyAnnotation(textBoundsCollection: textLines);
    }
    annotation.color = color;
    return annotation;
  }

  // -------------------------------------------------------------------------
  // Bookmark operations
  // -------------------------------------------------------------------------

  Future<void> addBookmark({String? note}) async {
    if (_bookmarks.any((b) => b.page == _currentPage)) {
      _log('Page $_currentPage already bookmarked');
      return;
    }
    final bm =
    Bookmark.create(pdfId: pdfId, page: _currentPage, note: note);
    final rowId = await BookmarkService.instance.addBookmark(bm);
    if (_disposed) return;
    _log('Bookmark added rowId=$rowId page=$_currentPage');
    final stored = bm.copyWith(id: rowId);
    final updated = List<Bookmark>.of(_bookmarks)..add(stored);
    updated.sort((a, b) => a.page.compareTo(b.page));
    _bookmarks = updated;
    bookmarksNotifier.notifyListeners();
  }

  Future<void> removeBookmark(int id) async {
    await BookmarkService.instance.removeBookmark(id);
    if (_disposed) return;
    _bookmarks =
        _bookmarks.where((b) => b.id != id).toList(growable: false);
    bookmarksNotifier.notifyListeners();
    _log('Bookmark removed id=$id');
  }

  Future<void> updateBookmarkNote(int id, String? note) async {
    await BookmarkService.instance.updateNote(id, note);
    if (_disposed) return;
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx != -1) {
      final updated = List<Bookmark>.of(_bookmarks);
      updated[idx] = updated[idx].copyWith(note: note);
      _bookmarks = updated;
    }
    bookmarksNotifier.notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Notes operations — text-anchored
  // -------------------------------------------------------------------------

  /// Saves a new text-anchored note and adds its in-PDF teal highlight
  /// annotation when [rectList] is non-empty.
  Future<Note> addNote({
    required String noteText,
    String selectedText = '',
    List<NoteRect> rectList = const [],
  }) async {
    final note = Note.create(
      pdfId: pdfId,
      page: _currentPage,
      noteText: noteText,
      selectedText: selectedText,
      rectList: rectList,
    );
    final rowId = await NoteService.instance.addNote(note);
    final stored = note.copyWith(id: rowId);

    if (!_disposed) {
      final updated = List<Note>.of(_notes)..add(stored);
      updated.sort((a, b) {
        final pc = a.page.compareTo(b.page);
        if (pc != 0) return pc;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      _notes = updated;
      _invalidateNoteCountCache(); // full cache invalidation after list mutation

      if (_hasRendered) _addNoteAnnotationToViewer(stored);

      notesNotifier.notifyListeners();
    }

    _log('Note added rowId=$rowId page=$_currentPage '
        'anchor="${selectedText.length > 20 ? selectedText.substring(0, 20) : selectedText}" '
        'rects=${rectList.length}');
    return stored;
  }

  Future<void> updateNote(int id, String text) async {
    await NoteService.instance.updateNote(id, text);
    if (_disposed) return;
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final updated = List<Note>.of(_notes);
      updated[idx] = updated[idx].copyWith(
        noteText: text,
        updatedAt: DateTime.now(),
      );
      _notes = updated;
    }
    notesNotifier.notifyListeners();
    _log('Note updated id=$id');
  }

  Future<void> removeNote(int id) async {
    final noteIdx = _notes.indexWhere((n) => n.id == id);
    if (noteIdx != -1 && _hasRendered) {
      _removeNoteAnnotationFromViewer(_notes[noteIdx]);
    }
    await NoteService.instance.removeNote(id);
    if (_disposed) return;
    _notes = _notes.where((n) => n.id != id).toList(growable: false);
    _invalidateNoteCountCache(); // invalidate after list mutation
    notesNotifier.notifyListeners();
    _log('Note removed id=$id');
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  Future<void> goToPage(int page) async {
    if (!_hasRendered) return;
    if (page == _currentPage) return;
    _currentPage = page;
    _updateNoteCountCache();
    pageNotifier.notifyListeners();
    _pendingJumpTarget = page;
    sfController.jumpToPage(page + 1);
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  Future<String> _extractAsset() async {
    final dir = await getTemporaryDirectory();
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
        _totalPages == _persistedTotalPages) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_kProgressDebounce, _persistProgress);
  }

  Future<void> _persistProgress() async {
    if (_disposed || _savingProgress) return;
    _savingProgress = true;
    savingNotifier.notifyListeners();
    try {
      await ProgressService.instance.saveProgress(
        ReadingProgress.create(
          pdfId: pdfId,
          currentPage: _currentPage,
          totalPages: _totalPages,
          title: pdfTitle,
          filePath: onDeviceFilePath,
        ),
      );
      _persistedPage = _currentPage;
      _persistedTotalPages = _totalPages;
      _log('[PROGRESS_SAVE] page=${_currentPage + 1} '
          'total=$_totalPages '
          'pct=${progressPct.toStringAsFixed(0)}% '
          '[CONTINUE_READING_UPDATE=done]');
    } catch (e) {
      _log('Progress save failed (non-fatal): $e');
    } finally {
      _savingProgress = false;
      if (!_disposed) savingNotifier.notifyListeners();
    }
  }

  void _persistProgressImmediate() {
    ProgressService.instance
        .saveProgress(ReadingProgress.create(
      pdfId: pdfId,
      currentPage: _currentPage,
      totalPages: _totalPages,
      title: pdfTitle,
      filePath: onDeviceFilePath,
    ))
        .then((_) {})
        .catchError((Object e) {
      _log('Dispose-time save failed: $e');
    });
  }

  Future<void> _reloadBookmarks() async {
    try {
      final loaded = await BookmarkService.instance.getBookmarks(pdfId);
      if (_disposed) return;
      _bookmarks = loaded;
      _log('Bookmarks: ${_bookmarks.length} for pdfId=$pdfId');
      bookmarksNotifier.notifyListeners();
    } catch (e) {
      _log('Failed to load bookmarks (non-fatal): $e');
    }
  }

  void _setLoading(bool v) {
    _loading = v;
    if (!_disposed) notifyListeners();
  }

  void _log(String msg) => debugPrint('[PdfViewerCtrl:$pdfId] $msg');
}

// ---------------------------------------------------------------------------
// PendingTextSelection
// ---------------------------------------------------------------------------

class PendingTextSelection {
  const PendingTextSelection({
    required this.selectedText,
    required this.globalRegion,
    required this.page,
    required this.textLines,
  });

  final String selectedText;
  final Rect? globalRegion;
  final int page;
  final List<sf.PdfTextLine> textLines;
}