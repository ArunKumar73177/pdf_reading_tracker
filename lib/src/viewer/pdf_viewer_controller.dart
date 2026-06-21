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

/// Source of truth for [PdfReadingTrackerViewer].
///
/// ## Annotation persistence — how it works (v2.6.0)
///
/// ### Verified Syncfusion 27.x annotation classes
/// All four text-markup classes share the same constructor signature:
/// ```dart
/// HighlightAnnotation(textBoundsCollection: List<PdfTextLine>)
/// UnderlineAnnotation(textBoundsCollection: List<PdfTextLine>)
/// StrikethroughAnnotation(textBoundsCollection: List<PdfTextLine>)
/// SquigglyAnnotation(textBoundsCollection: List<PdfTextLine>)
/// ```
/// All inherit `color`, `opacity`, `pageNumber` from `Annotation`.
///
/// ### Page number boundary (unchanged)
/// - Stored [Highlight.page] / [Note.page]: **zero-based**.
/// - Syncfusion `pageNumber`: **one-based**.
///
/// ### Lifecycle safety
/// [init] performs two `await`s before touching any state. [_disposed]
/// guards every state-mutating method against a dispose-during-init race.
///
/// ### v2.6.0 — standalone Notes
/// Notes are now a fully independent concept from [Highlight] annotations,
/// backed by [NoteService] / the `notes` table. See [Note]'s doc comment.
/// The crash-prone in-bar note dialog has been removed entirely — note
/// editing is delegated to `SafeNoteDialog`, opened by the viewer widget on
/// the root Navigator, with this controller only persisting the result.
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

  final ChangeNotifier pageNotifier = ChangeNotifier();
  final ChangeNotifier bookmarksNotifier = ChangeNotifier();
  final ChangeNotifier savingNotifier = ChangeNotifier();
  final ChangeNotifier highlightNotifier = ChangeNotifier();
  final ChangeNotifier notesNotifier = ChangeNotifier();

  ChangeNotifier get searchNotifier => searchController.notifier;

  // ---------------------------------------------------------------------------
  // Disposal guard
  // ---------------------------------------------------------------------------

  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Exposed state
  // ---------------------------------------------------------------------------

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

  double get progressPct {
    if (_totalPages <= 0) return 0.0;
    return ((_currentPage + 1) / _totalPages * 100.0).clamp(0.0, 100.0);
  }

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  List<Highlight> _highlights = [];
  List<Highlight> get highlights => List.unmodifiable(_highlights);

  List<Note> _notes = [];
  List<Note> get notes => List.unmodifiable(_notes);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // ---------------------------------------------------------------------------
  // Pending text selection
  // ---------------------------------------------------------------------------

  PendingTextSelection? _pendingSelection;
  PendingTextSelection? get pendingSelection => _pendingSelection;

  // ---------------------------------------------------------------------------
  // Internal flags
  // ---------------------------------------------------------------------------

  bool _hasRendered = false;
  int? _pendingJumpTarget;
  int _persistedPage = -1;
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
    _error = null;
    _hasRendered = false;
    _pendingJumpTarget = null;
    _pendingSelection = null;

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
        if (_disposed) return;
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
    _log('Restored page $_currentPage / $_totalPages');
  }

  @override
  void dispose() {
    if (_progressDebounce?.isActive == true) {
      _progressDebounce!.cancel();
      _persistProgressImmediate();
    }
    _progressDebounce?.cancel();
    _disposed = true;
    searchController.dispose();
    pageNotifier.dispose();
    bookmarksNotifier.dispose();
    savingNotifier.dispose();
    highlightNotifier.dispose();
    notesNotifier.dispose();
    sfController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Syncfusion document callbacks
  // ---------------------------------------------------------------------------

  void onPageChanged(int newPageNumber) {
    if (_disposed) return;
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
    if (_disposed) return;
    _totalPages = pageCount;
    pageNotifier.notifyListeners();

    if (!_hasRendered) {
      _hasRendered = true;
      _reloadBookmarks();
      _reloadNotes();
      _loadAndRestoreAnnotations();
      _schedulePersistProgress();
    }
  }

  void onDocumentLoadFailed(String description) {
    if (_disposed) return;
    _error = 'Failed to load PDF: $description';
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Text selection capture
  // ---------------------------------------------------------------------------

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
      }
      return;
    }
    _pendingSelection = PendingTextSelection(
      selectedText: selectedText,
      globalRegion: globalRegion,
      page: _currentPage,
      textLines: textLines ?? const [],
    );
    highlightNotifier.notifyListeners();
  }

  /// Clears any active PDF text selection, tearing down Syncfusion's native
  /// selection-handle overlay.
  ///
  /// **Must be called before opening any dialog over the PDF viewer.**
  /// Syncfusion's selection handles live in a platform-level overlay
  /// outside Flutter's widget tree; if left active while a dialog has
  /// focus, they can continue firing `onTextSelectionChanged` and corrupt
  /// unrelated element trees. This is the fix for the
  /// `TextEditingController used after disposed` / duplicate-`GlobalKey`
  /// crash family — selection is always torn down first.
  void clearPdfSelection() {
    try {
      sfController.clearSelection();
    } catch (_) {
      // No active selection / controller not yet attached — safe to ignore.
    }
  }

  // ---------------------------------------------------------------------------
  // Annotation: commit
  // ---------------------------------------------------------------------------

  Future<void> commitAnnotation({
    required List<sf.PdfTextLine> textLines,
    required AnnotationCommit commit,
  }) async {
    final pending = _pendingSelection;
    _pendingSelection = null;

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

    final zeroPage = textLines.isNotEmpty
        ? textLines.first.pageNumber - 1
        : (pending?.page ?? _currentPage);

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

  // ---------------------------------------------------------------------------
  // Annotation: note (legacy per-annotation note — unchanged)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Annotation: remove
  // ---------------------------------------------------------------------------

  Future<void> removeHighlight(int id) async {
    final idx = _highlights.indexWhere((h) => h.id == id);
    if (idx == -1) {
      _log('removeHighlight: id=$id not found in memory list');
      return;
    }

    final stored = _highlights[idx];
    _removeSfAnnotation(stored);

    await HighlightService.instance.removeHighlight(id);
    if (_disposed) return;

    _highlights = _highlights.where((h) => h.id != id).toList(growable: false);
    _log('Annotation removed id=$id');
    highlightNotifier.notifyListeners();
  }

  void _removeSfAnnotation(Highlight highlight) {
    final sfPage = highlight.page + 1;

    final sameTypeOnPage = _highlights
        .where((h) => h.page == highlight.page && h.annotationType == highlight.annotationType)
        .toList(growable: false);
    final relativeIdx = sameTypeOnPage.indexWhere((h) => h.id == highlight.id);

    final sfOnPage = _sfAnnotationsOfType(highlight.annotationType)
        .where((a) => a.pageNumber == sfPage)
        .toList(growable: false);

    if (relativeIdx >= 0 && relativeIdx < sfOnPage.length) {
      sfController.removeAnnotation(sfOnPage[relativeIdx]);
      return;
    }

    if (sfOnPage.isNotEmpty) {
      sfController.removeAnnotation(sfOnPage.first);
      _log('_removeSfAnnotation: fallback used for '
          'id=${highlight.id} page=${highlight.page}');
      return;
    }

    _log('_removeSfAnnotation: no Syncfusion annotation found for '
        'id=${highlight.id} page=${highlight.page}');
  }

  List<sf.Annotation> _sfAnnotationsOfType(AnnotationType type) {
    final all = sfController.getAnnotations();
    switch (type) {
      case AnnotationType.highlight:
        return all.whereType<sf.HighlightAnnotation>().toList();
      case AnnotationType.underline:
        return all.whereType<sf.UnderlineAnnotation>().toList();
      case AnnotationType.strikethrough:
        return all.whereType<sf.StrikethroughAnnotation>().toList();
      case AnnotationType.squiggly:
        return all.whereType<sf.SquigglyAnnotation>().toList();
    }
  }

  // ---------------------------------------------------------------------------
  // Annotation: load from SQLite and restore to Syncfusion viewer
  // ---------------------------------------------------------------------------

  Future<void> _loadAndRestoreAnnotations() async {
    try {
      final loaded = await HighlightService.instance.getHighlights(pdfId);
      if (_disposed) return;
      _highlights = loaded;
      _log('Annotations loaded: ${_highlights.length} for pdfId=$pdfId');
    } catch (e) {
      if (_disposed) return;
      _log('Failed to load annotations (non-fatal): $e');
      _highlights = [];
    }

    if (_disposed) return;
    highlightNotifier.notifyListeners();
    _restoreAnnotationsToViewer();
  }

  void _restoreAnnotationsToViewer() {
    for (final highlight in _highlights) {
      try {
        if (highlight.rectList.isEmpty) {
          _log('Skipping restore for id=${highlight.id}: empty rectList');
          continue;
        }

        final textLines = highlight.rectList
            .map((r) => sf.PdfTextLine(
          Rect.fromLTRB(r.left, r.top, r.right, r.bottom),
          highlight.selectedText,
          highlight.page + 1,
        ))
            .toList(growable: false);

        final sfAnnotation = _buildSfAnnotation(
          type: highlight.annotationType,
          textLines: textLines,
          color: Color(highlight.colorValue),
        );

        sfController.addAnnotation(sfAnnotation);
      } catch (e) {
        _log('Failed to restore annotation id=${highlight.id} '
            'page=${highlight.page}: $e');
      }
    }
    _log('Annotations restored to viewer: ${_highlights.length}');
  }

  // ---------------------------------------------------------------------------
  // Syncfusion annotation builder
  // ---------------------------------------------------------------------------

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
        annotation = sf.StrikethroughAnnotation(textBoundsCollection: textLines);
      case AnnotationType.squiggly:
        annotation = sf.SquigglyAnnotation(textBoundsCollection: textLines);
    }
    annotation.color = color;
    return annotation;
  }

  // ---------------------------------------------------------------------------
  // Bookmark operations (unchanged)
  // ---------------------------------------------------------------------------

  Future<void> addBookmark({String? note}) async {
    if (_bookmarks.any((b) => b.page == _currentPage)) {
      _log('Page $_currentPage already bookmarked');
      return;
    }
    final bm = Bookmark.create(pdfId: pdfId, page: _currentPage, note: note);
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
    _log('Bookmark removed id=$id');
    _bookmarks = _bookmarks.where((b) => b.id != id).toList(growable: false);
    bookmarksNotifier.notifyListeners();
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

  // ---------------------------------------------------------------------------
  // Notes operations (v2.6.0 — standalone notes)
  // ---------------------------------------------------------------------------

  /// Adds a new note on the current page. Returns the saved [Note].
  Future<Note> addNote(String text) async {
    final note = Note.create(pdfId: pdfId, page: _currentPage, text: text);
    final rowId = await NoteService.instance.addNote(note);
    final stored = note.copyWith(id: rowId);
    if (!_disposed) {
      final updated = List<Note>.of(_notes)..add(stored);
      updated.sort((a, b) {
        final pageCompare = a.page.compareTo(b.page);
        if (pageCompare != 0) return pageCompare;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      _notes = updated;
      notesNotifier.notifyListeners();
    }
    _log('Note added rowId=$rowId page=$_currentPage');
    return stored;
  }

  /// Updates an existing note's text.
  Future<void> updateNote(int id, String text) async {
    await NoteService.instance.updateNote(id, text);
    if (_disposed) return;
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final updated = List<Note>.of(_notes);
      updated[idx] = updated[idx].copyWith(text: text, updatedAt: DateTime.now());
      _notes = updated;
    }
    notesNotifier.notifyListeners();
    _log('Note updated id=$id');
  }

  /// Deletes a note.
  Future<void> removeNote(int id) async {
    await NoteService.instance.removeNote(id);
    if (_disposed) return;
    _notes = _notes.where((n) => n.id != id).toList(growable: false);
    notesNotifier.notifyListeners();
    _log('Note removed id=$id');
  }

  Future<void> _reloadNotes() async {
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
    if (!_disposed) notesNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Navigation (unchanged)
  // ---------------------------------------------------------------------------

  Future<void> goToPage(int page) async {
    if (!_hasRendered) return;
    if (page == _currentPage) return;
    _currentPage = page;
    pageNotifier.notifyListeners();
    _pendingJumpTarget = page;
    sfController.jumpToPage(page + 1);
  }

  // ---------------------------------------------------------------------------
  // Private helpers (unchanged)
  // ---------------------------------------------------------------------------

  Future<String> _extractAsset() async {
    final dir = await getTemporaryDirectory();
    final safe = pdfId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safe.pdf');
    if (!file.existsSync()) {
      _log('Extracting $assetPath -> ${file.path}');
      final data = await rootBundle.load(assetPath!);
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } else {
      _log('Asset already cached: ${file.path}');
    }
    return file.path;
  }

  void _schedulePersistProgress() {
    if (_currentPage == _persistedPage && _totalPages == _persistedTotalPages) return;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_kProgressDebounce, _persistProgress);
  }

  Future<void> _persistProgress() async {
    if (_savingProgress) return;
    _savingProgress = true;
    if (!_disposed) savingNotifier.notifyListeners();
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
        .catchError((e) => _log('Dispose-time save failed: $e'));
  }

  Future<void> _reloadBookmarks() async {
    final loaded = await BookmarkService.instance.getBookmarks(pdfId);
    if (_disposed) return;
    _bookmarks = loaded;
    _log('Bookmarks: ${_bookmarks.length} for pdfId=$pdfId');
    bookmarksNotifier.notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    if (!_disposed) notifyListeners();
  }

  void _log(String msg) => debugPrint('[PdfViewerCtrl:$pdfId] $msg');
}

// ---------------------------------------------------------------------------
// PendingTextSelection (unchanged)
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