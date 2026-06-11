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
/// This class is **internal to the package** and is not exported.
/// Consumers interact exclusively with [PdfReadingTrackerViewer].
///
/// Responsibilities:
///  - Extract asset / network PDF to a temp file for [alh_pdf_view].
///  - Guarantee a reading_progress FK-anchor row before any bookmark write.
///  - Persist progress on every page change.
///  - Load / add / remove bookmarks, keeping in-memory state in sync.
class PdfViewerController extends ChangeNotifier {
  PdfViewerController({
    required this.pdfId,
    required this.pdfTitle,
    required this.assetPath,
  });

  /// Unique, stable key for this PDF — used as the SQLite pdf_id.
  final String pdfId;

  /// Human-readable title shown in the app bar.
  final String pdfTitle;

  /// Flutter asset path, e.g. `'assets/docs/sample.pdf'`.
  final String assetPath;

  // ---------------------------------------------------------------------------
  // Exposed state
  // ---------------------------------------------------------------------------

  bool _loading = true;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  String? _filePath;
  String? get filePath => _filePath;

  AlhPdfViewController? _pdfViewController;

  int _initialPage = 0;
  int get initialPage => _initialPage;

  int _currentPage = 0;
  int get currentPage => _currentPage;

  int _totalPages = 0;
  int get totalPages => _totalPages;

  double get progressPct =>
      _totalPages > 0
          ? (_currentPage / _totalPages * 100).clamp(0.0, 100.0)
          : 0.0;

  List<Bookmark> _bookmarks = [];

  /// An unmodifiable view of the current bookmark list.
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Must be called once from [State.initState].
  ///
  /// Strict initialisation order:
  ///  1. Extract asset → temp file  (no DB dependency)
  ///  2. Ensure FK-anchor progress row exists
  ///  3. Restore saved page
  ///  4. Load bookmarks
  Future<void> init() async {
    _log('init() pdfId=$pdfId');
    _setLoading(true);
    _error = null;

    try {
      _filePath = await _extractAsset();
      await _ensureProgressExists();

      final saved = await ProgressService.instance.getProgress(pdfId);
      if (saved != null) {
        _initialPage = saved.currentPage;
        _currentPage = saved.currentPage;
        _totalPages  = saved.totalPages;
        _log('Restored page $_currentPage / $_totalPages');
      }

      await _reloadBookmarks();
    } catch (e, st) {
      debugPrintStack(stackTrace: st, label: 'PdfViewerController.init');
      _error = 'Failed to load PDF: $e';
    } finally {
      _setLoading(false);
    }
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
    _totalPages  = total;
    notifyListeners();
    await _persistProgress();
  }

  void onRender(int pages) {
    _totalPages = pages;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Bookmark operations
  // ---------------------------------------------------------------------------

  /// Adds a bookmark on the current page, optionally with a [note].
  ///
  /// No-op if the page is already bookmarked.
  /// Throws [BookmarkServiceException] on DB failure so the widget can
  /// surface a SnackBar.
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

  /// Navigates to [page] with animation.
  Future<void> goToPage(int page) async {
    await _pdfViewController?.setPage(page: page, withAnimation: true);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Copies the Flutter asset to a per-pdf temp file. Returns the path.
  ///
  /// Uses [pdfId] (sanitised) as the filename to avoid collisions and allow
  /// caching across hot-restarts.
  Future<String> _extractAsset() async {
    final dir  = await getTemporaryDirectory();
    final safe = pdfId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final file = File('${dir.path}/$safe.pdf');

    if (!file.existsSync()) {
      _log('Extracting $assetPath → ${file.path}');
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } else {
      _log('Asset already cached: ${file.path}');
    }
    return file.path;
  }

  /// Creates a sentinel progress row when none exists.
  ///
  /// The bookmarks table has a FOREIGN KEY on reading_progress(pdf_id).
  /// Without this guard, the very first bookmark INSERT on a fresh install
  /// silently fails with a FK violation.
  Future<void> _ensureProgressExists() async {
    final existing = await ProgressService.instance.getProgress(pdfId);
    if (existing == null) {
      await ProgressService.instance.saveProgress(
        ReadingProgress.create(
          pdfId: pdfId,
          currentPage: 0,
          totalPages: 0,
          title: pdfTitle,
        ),
      );
      _log('FK-anchor row created');
    }
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