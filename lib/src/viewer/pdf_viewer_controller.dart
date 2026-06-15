import 'dart:async';
import 'dart:io';

import 'package:alh_pdf_view/alh_pdf_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/bookmark.dart';
import '../models/reading_progress.dart';
import '../services/bookmark_service.dart';
import '../services/progress_service.dart';

/// Source of truth for [PdfReadingTrackerViewer].
///
/// **v2.1.0 performance changes**
/// - `init()` now issues a single DB call ([ProgressService.getOrCreate]) instead
///   of two sequential calls (`_ensureProgressExists` + `getProgress`).
/// - Progress saves are debounced (300 ms) so rapid page-turn sequences produce
///   one write rather than N writes.
/// - `goToPage` is guarded against duplicate calls to the same page index.
///
/// Supports two PDF sources:
/// - **Asset PDF**: pass [assetPath]; the controller extracts it to a temp file.
/// - **User-picked PDF**: pass [filePath] directly; no extraction needed.
///
/// Exactly one of [assetPath] or [filePath] must be non-null.
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

  /// Flutter asset path, e.g. `'assets/docs/sample.pdf'`. Mutually exclusive
  /// with [filePath].
  final String? assetPath;

  /// Absolute on-device file path for user-picked PDFs. Mutually exclusive
  /// with [assetPath].
  final String? filePath;

  /// Absolute on-device file path stored in the progress record.
  /// Used so the Recent PDFs list can verify the file still exists.
  final String? onDeviceFilePath;

  // ---------------------------------------------------------------------------
  // Exposed state
  // ---------------------------------------------------------------------------

  bool _loading = true;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  String? _resolvedFilePath;
  String? get resolvedFilePath => _resolvedFilePath;

  AlhPdfViewController? _pdfViewController;

  int _initialPage = 0;
  int get initialPage => _initialPage;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  int _totalPages = 0;
  int get totalPages => _totalPages;

  double get progressPct => _totalPages > 0
      ? (_currentPage / _totalPages * 100).clamp(0.0, 100.0)
      : 0.0;

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // ---------------------------------------------------------------------------
  // Debounce
  // ---------------------------------------------------------------------------

  Timer? _progressDebounce;

  /// How long to wait after the last page change before writing to SQLite.
  static const _kProgressDebounce = Duration(milliseconds: 300);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _log('init() pdfId=$pdfId');
    _setLoading(true);
    _error = null;

    try {
      // File resolution and DB bootstrap run concurrently when possible.
      // Asset extraction must happen first so we have a valid file path;
      // for user-picked PDFs we can parallelise file resolution with the DB
      // call since filePath is already known.
      if (filePath != null) {
        // Parallel: resolve path + bootstrap DB record.
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
        // Asset PDF: must extract before DB call (pdfId is stable, filePath is null).
        _resolvedFilePath = await _extractAsset();
        final saved = await ProgressService.instance.getOrCreate(
          pdfId: pdfId,
          pdfTitle: pdfTitle,
          onDeviceFilePath: onDeviceFilePath,
        );
        _applyProgress(saved);
      }

      await _reloadBookmarks();
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
    _totalPages = saved.totalPages;
    _log('Restored page $_currentPage / $_totalPages');
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // alh_pdf_view callbacks
  // ---------------------------------------------------------------------------

  void onViewCreated(AlhPdfViewController controller) {
    _pdfViewController = controller;
    notifyListeners();
  }

  Future<void> onPageChanged(int page, int total) async {
    _currentPage = page;
    _totalPages = total;
    notifyListeners();
    _schedulePersistProgress();
  }

  void onRender(int pages) {
    _totalPages = pages;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Bookmark operations
  // ---------------------------------------------------------------------------

  /// Adds a bookmark on [currentPage], optionally with a [note].
  ///
  /// No-op if the page is already bookmarked.
  Future<void> addBookmark({String? note}) async {
    if (_bookmarks.any((b) => b.page == _currentPage)) {
      _log('Page $_currentPage already bookmarked');
      return;
    }
    final bm = Bookmark.create(pdfId: pdfId, page: _currentPage, note: note);
    final rowId = await BookmarkService.instance.addBookmark(bm);
    _log('Bookmark added rowId=$rowId page=$_currentPage');
    await _reloadBookmarks();
  }

  /// Removes the bookmark identified by [id].
  Future<void> removeBookmark(int id) async {
    await BookmarkService.instance.removeBookmark(id);
    _log('Bookmark removed id=$id');
    await _reloadBookmarks();
  }

  /// Updates the note on the bookmark identified by [id].
  ///
  /// Pass `null` to [note] to clear an existing note.
  Future<void> updateBookmarkNote(int id, String? note) async {
    await BookmarkService.instance.updateNote(id, note);
    _log('Bookmark note updated id=$id');
    await _reloadBookmarks();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Navigates to the given zero-based [page] with animation.
  ///
  /// No-op if [page] equals [currentPage] (prevents redundant renders).
  Future<void> goToPage(int page) async {
    if (page == _currentPage) return;
    await _pdfViewController?.setPage(page: page, withAnimation: true);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<String> _extractAsset() async {
    final dir = await getTemporaryDirectory();
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

  /// Debounced version of [_persistProgress].
  ///
  /// Rapid page-turn callbacks (swipe bursts, jump-to-page) collapse into a
  /// single write that fires [_kProgressDebounce] after the last call.
  void _schedulePersistProgress() {
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_kProgressDebounce, _persistProgress);
  }

  Future<void> _persistProgress() async {
    if (_savingProgress) return;
    _savingProgress = true;
    notifyListeners();
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
    } catch (e) {
      _log('Progress save failed (non-fatal): $e');
    } finally {
      _savingProgress = false;
      notifyListeners();
    }
  }

  Future<void> _reloadBookmarks() async {
    _bookmarks = await BookmarkService.instance.getBookmarks(pdfId);
    _log('Bookmarks: ${_bookmarks.length} for pdfId=$pdfId');
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _log(String msg) => debugPrint('[PdfViewerCtrl:$pdfId] $msg');
}