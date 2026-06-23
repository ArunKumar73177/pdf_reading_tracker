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
// Note annotation color — teal at 55 % opacity
// ---------------------------------------------------------------------------

const int _kNoteAnnotationColor = 0x8C00BCD4;

// ---------------------------------------------------------------------------
// PdfViewerController
// ---------------------------------------------------------------------------

/// Source of truth for [PdfReadingTrackerViewer].
///
/// ### Bug 3 fix — onPageChanged demoted to fallback
///
/// Syncfusion's `onPageChanged` fires based on the **top edge** of the
/// visible area: whichever page's top is closest to the viewport top is
/// reported as the current page. This is wrong when two pages are visible
/// and the lower page occupies most of the screen.
///
/// The fix is split across two files:
///
/// 1. `pdf_reading_tracker_viewer.dart` — a `_scrollDetectionActive` flag
///    gates calls to [onPageChanged]. Once the first
///    [ScrollUpdateNotification] fires, [onPageChanged] is no longer
///    forwarded here; [onScrollUpdate]'s midpoint algorithm is authoritative.
///
/// 2. This file — [goToPage] installs a 1.5 s timeout to auto-clear
///    `_pendingJumpTarget`. Without the timeout, a rendering delay or scroll
///    overshoot could leave the guard set indefinitely, silently swallowing
///    all subsequent [onScrollUpdate] page detections.
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
  int get noteCountOnCurrentPage => _noteCountOnCurrentPage;

  void _updateNoteCountCache() {
    if (_noteCountCachedPage == _currentPage) return;
    _noteCountCachedPage = _currentPage;
    _noteCountOnCurrentPage =
        _notes.where((n) => n.page == _currentPage).length;
  }

  void _invalidateNoteCountCache() {
    _noteCountCachedPage = -1;
    _updateNoteCountCache();
  }

  // -------------------------------------------------------------------------
  // Text selection — live pending + stable snapshot
  // -------------------------------------------------------------------------

  PendingTextSelection? _pendingSelection;
  PendingTextSelection? get pendingSelection => _pendingSelection;

  PendingTextSelection? _selectionSnapshot;
  PendingTextSelection? get snapshotSelection => _selectionSnapshot;

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

  /// Fallback page update from Syncfusion's `onPageChanged` (top-edge).
  ///
  /// ### Bug 3 fix
  /// The viewer layer gates calls to this method behind
  /// `!_scrollDetectionActive`. It is only called before the first scroll
  /// event fires — i.e., for the initial page restore after document load.
  /// Once the user scrolls, [onScrollUpdate]'s midpoint algorithm is the
  /// sole authority and this method is never forwarded from the viewer.
  void onPageChanged(int newPageNumber) {
    if (_disposed) return;
    _updateCurrentPage(newPageNumber - 1, source: 'onPageChanged');
  }

  /// Called by [NotificationListener<ScrollUpdateNotification>] in the viewer.
  ///
  /// Computes the dominant visible page using the viewport midpoint:
  ///
  ///   pageH          = maxScrollExtent / (totalPages − 1)
  ///   viewportCenter = pixels + viewportDimension / 2
  ///   dominant       = floor(viewportCenter / pageH) + 1   [clamped]
  ///
  /// The page occupying the largest visible fraction is always the one whose
  /// top is closest to (and below) the viewport center.
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
      final candidate = sfController.pageNumber;
      if (candidate >= 1) {
        _updateCurrentPage(candidate - 1, source: 'onScrollUpdate:fallback');
      }
      return;
    }

    final pageH = _lastMaxScrollExtent / (_totalPages - 1).toDouble();
    final viewportCenter =
        metrics.pixels + (metrics.viewportDimension / 2.0);
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
  void _updateCurrentPage(int zeroBasedPage, {required String source}) {
    if (_pendingJumpTarget != null && zeroBasedPage != _pendingJumpTarget) {
      return;
    }
    _pendingJumpTarget = null;
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

    final selectionPage = (textLines != null && textLines.isNotEmpty)
        ? textLines.first.pageNumber - 1
        : _currentPage;

    final sel = PendingTextSelection(
      selectedText: selectedText,
      globalRegion: globalRegion,
      page: selectionPage,
      textLines: textLines ?? const [],
    );
    _pendingSelection = sel;
    _selectionSnapshot = sel;
    highlightNotifier.notifyListeners();
  }

  void clearPdfSelection() {
    try {
      sfController.clearSelection();
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Annotation: commit
  // -------------------------------------------------------------------------

  Future<void> commitAnnotation({
    required List<sf.PdfTextLine> textLines,
    required AnnotationCommit commit,
  }) async {
    final pending = _pendingSelection;
    _pendingSelection = null;
    _selectionSnapshot = null;

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
    final allAnnotations = sfController.getAnnotations();

    final sameTypeOnPage = _highlights
        .where((h) =>
    h.page == highlight.page &&
        h.annotationType == highlight.annotationType)
        .toList(growable: false);
    final relativeIdx =
    sameTypeOnPage.indexWhere((h) => h.id == highlight.id);

    final sfOnPage =
    _sfAnnotationsOfType(highlight.annotationType, allAnnotations)
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
        return allAnnotations
            .whereType<sf.StrikethroughAnnotation>()
            .toList();
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
  // Notes operations
  // -------------------------------------------------------------------------

  Future<Note> addNote({
    required String noteText,
    String selectedText = '',
    List<NoteRect> rectList = const [],
    int? page,
  }) async {
    final notePage = page ?? _currentPage;
    final note = Note.create(
      pdfId: pdfId,
      page: notePage,
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
      _invalidateNoteCountCache();

      if (_hasRendered) _addNoteAnnotationToViewer(stored);

      notesNotifier.notifyListeners();
    }

    _log('Note added rowId=$rowId page=$notePage '
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
    _invalidateNoteCountCache();
    notesNotifier.notifyListeners();
    _log('Note removed id=$id');
  }

  // -------------------------------------------------------------------------
  // Navigation
  //
  // Bug 3 fix: auto-clear _pendingJumpTarget after 1.5 s.
  //
  // _pendingJumpTarget guards _updateCurrentPage: while it is set, only the
  // exact target page is accepted and all other scroll updates are swallowed.
  // This is correct during the brief window after jumpToPage() while
  // Syncfusion is animating to the target. However, if a rendering delay or
  // scroll overshoot prevents the exact target page from arriving via
  // onScrollUpdate, _pendingJumpTarget would stay set indefinitely, blocking
  // all future page detection.
  //
  // The 1.5 s timeout guarantees the guard is cleared regardless of what
  // Syncfusion reports.
  // -------------------------------------------------------------------------

  Future<void> goToPage(int page) async {
    if (!_hasRendered) return;
    if (page == _currentPage) return;
    _currentPage = page;
    _updateProgressPct();
    _updateNoteCountCache();
    pageNotifier.notifyListeners();
    _pendingJumpTarget = page;
    sfController.jumpToPage(page + 1);

    // Bug 3 fix: bounded guard — never blocks scroll detection indefinitely.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!_disposed && _pendingJumpTarget == page) {
        _pendingJumpTarget = null;
      }
    });
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
    final savedPdfId = pdfId;
    final savedPage = _currentPage;
    final savedTotalPages = _totalPages;
    final savedTitle = pdfTitle;
    final savedFilePath = onDeviceFilePath;

    ProgressService.instance
        .saveProgress(ReadingProgress.create(
      pdfId: savedPdfId,
      currentPage: savedPage,
      totalPages: savedTotalPages,
      title: savedTitle,
      filePath: savedFilePath,
    ))
        .then((_) {})
        .catchError((Object e) {
      debugPrint('[PdfViewerCtrl:$savedPdfId] Dispose-time save failed: $e');
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

  /// Zero-based page derived from [textLines.first.pageNumber] — authoritative.
  final int page;

  final List<sf.PdfTextLine> textLines;
}