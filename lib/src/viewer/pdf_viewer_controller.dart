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
/// **v2.1.1 changes**
///
/// Bug 2 & 3 — Progress percentage:
///   `progressPct` now uses `(currentPage + 1) / totalPages` so page 1 shows
///   a non-zero percentage and the last page always shows 100 %.
///
/// Bug 4 — Jump-to-page performance:
///   `goToPage` no longer triggers a bookmark reload or an extra
///   `notifyListeners` call.  The debounce was already in place; we now also
///   guard against the `setState` storm that happened when the PDF renderer
///   emitted rapid `onPageChanged` events during a programmatic jump.
///
/// Bug 5 — Open performance:
///   Bookmark loading is deferred until after the first render (`onRender`).
///   This removes a blocking SQLite query from the critical open path.
///
/// Bug 6 — Continue Reading / Recent:
///   An initial progress record is written immediately in `init()` so the PDF
///   appears in Recent PDFs before the user scrolls a single page.
///
/// **v2.2.0 change — Improvement 2 (jump-to-page optimisation)**
///   The previous implementation waited 50 ms inside `goToPage` before
///   updating `_currentPage`, causing a visible lag between the user tapping
///   "Go" and the progress bar / page counter reflecting the new position.
///
///   Fix: `_currentPage` is now updated **optimistically** (before the
///   `setPage` call), so the UI reacts instantly.  `_jumping` is set to
///   `true` before the native scroll begins and cleared in `finally`, which
///   continues to suppress the intermediate `onPageChanged` callbacks emitted
///   by the renderer during the animation.  A single `notifyListeners` +
///   debounced progress save fires once `setPage` awaits — eliminating both
///   the rebuild storm and the redundant SQLite writes.
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

  /// Bug 2 & 3 fix: use (currentPage + 1) / totalPages so that:
  ///   - index 0 (page 1)       → 1/N * 100  > 0 %
  ///   - index N-1 (last page)  → N/N * 100  = 100 %
  double get progressPct {
    if (_totalPages <= 0) return 0.0;
    return ((_currentPage + 1) / _totalPages * 100.0).clamp(0.0, 100.0);
  }

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);

  bool _savingProgress = false;
  bool get isSavingProgress => _savingProgress;

  // ---------------------------------------------------------------------------
  // Internal flags
  // ---------------------------------------------------------------------------

  /// Tracks whether the very first `onRender` has fired.
  /// Used to defer bookmark loading until the PDF is actually visible.
  bool _hasRendered = false;

  /// Tracks whether a programmatic `goToPage` jump is in progress.
  /// While true, `onPageChanged` callbacks are suppressed from triggering
  /// progress saves and extra `notifyListeners` calls to avoid rebuild storms.
  bool _jumping = false;

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
    _hasRendered = false;

    try {
      // File resolution and DB bootstrap run concurrently when possible.
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
        _resolvedFilePath = await _extractAsset();
        final saved = await ProgressService.instance.getOrCreate(
          pdfId: pdfId,
          pdfTitle: pdfTitle,
          onDeviceFilePath: onDeviceFilePath,
        );
        _applyProgress(saved);
      }

      // Bug 6 fix: write an initial progress record immediately so the PDF
      // appears in Recent PDFs as soon as it is opened, before any page
      // scroll occurs.  If totalPages is still 0 (renderer hasn't fired yet)
      // we write with page=0/total=0 and let onRender update total later.
      await _persistProgressImmediate();

      // Bookmarks are deferred to onRender (Bug 5 fix — see below).
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
    // Do not call notifyListeners here — the widget rebuilds via onRender.
  }

  /// Called by alh_pdf_view on every page change (swipe, programmatic jump).
  ///
  /// During a programmatic jump ([_jumping] == true) we update state silently
  /// without scheduling a progress save or triggering a rebuild — the jump
  /// completion handler does both after the animation settles.
  Future<void> onPageChanged(int page, int total) async {
    _currentPage = page;
    _totalPages = total;

    if (_jumping) {
      // State is updated above so progressPct is correct, but we skip the
      // expensive notify + SQLite write during the jump animation.
      return;
    }

    notifyListeners();
    _schedulePersistProgress();
  }

  /// Called once by alh_pdf_view when the PDF has finished rendering.
  ///
  /// Bug 5 fix: bookmarks are loaded here (after first render) rather than
  /// in init(), keeping the critical open path free of extra SQLite reads.
  ///
  /// Bug 6 fix: we persist progress with the now-known totalPages so the
  /// Recent PDFs list shows correct page counts.
  void onRender(int pages) {
    _totalPages = pages;
    notifyListeners();

    if (!_hasRendered) {
      _hasRendered = true;
      // Load bookmarks lazily after the first render.
      _reloadBookmarks();
      // Persist with the real totalPages value.
      _schedulePersistProgress();
    }
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
  // Navigation — Improvement 2: optimistic page update, no 50 ms delay
  // ---------------------------------------------------------------------------

  /// Navigates to the given zero-based [page] with animation.
  ///
  /// No-op if [page] equals [currentPage] (prevents redundant renders).
  ///
  /// ### Optimisation (v2.2.0)
  /// `_currentPage` is updated **before** calling `setPage` so the progress
  /// bar and page counter reflect the target page instantly, giving the user
  /// immediate visual feedback while the native scroll animation plays.
  ///
  /// `_jumping` is set to `true` for the full duration of the await so every
  /// intermediate `onPageChanged` callback emitted by the renderer is silently
  /// absorbed (state update only, no `notifyListeners`, no SQLite write).
  ///
  /// A single `notifyListeners` + debounced save fires once `setPage` returns,
  /// ensuring exactly one rebuild and at most one SQLite write per jump.
  Future<void> goToPage(int page) async {
    if (page == _currentPage) return;

    // ── Optimistic update ────────────────────────────────────────────────────
    // Update _currentPage immediately so the progress bar and counter react
    // at tap-time rather than after the scroll animation completes.
    _currentPage = page;
    notifyListeners(); // single rebuild — reflects the target state instantly

    _jumping = true;
    try {
      await _pdfViewController?.setPage(page: page, withAnimation: true);
      // No delay needed: _currentPage is already correct, and intermediate
      // onPageChanged callbacks are suppressed by _jumping == true.
    } finally {
      _jumping = false;
    }

    // One debounced save after the animation settles.
    // notifyListeners() is intentionally NOT called again here — the
    // optimistic notify above already reflected the correct state.
    _schedulePersistProgress();
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

  /// Immediate (non-debounced) progress write used during init to register
  /// the PDF in Recent / Continue Reading before the user scrolls.
  Future<void> _persistProgressImmediate() async {
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
      _log('Initial progress save failed (non-fatal): $e');
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