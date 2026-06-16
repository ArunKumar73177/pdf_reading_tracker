import 'package:alh_pdf_view/alh_pdf_view.dart';
import 'package:flutter/material.dart';
import '../services/bookmark_service.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/bookmark_fab.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/reader_bottom_bar.dart';

// ---------------------------------------------------------------------------
// Theme data-class (unchanged)
// ---------------------------------------------------------------------------

@immutable
class PdfViewerTheme {
  const PdfViewerTheme({
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.progressBarColor,
  });
  final Color? appBarBackgroundColor;
  final Color? appBarForegroundColor;
  final Color? progressBarColor;
}

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// A complete, self-contained PDF reader widget.
///
/// Supports two PDF sources — mutually exclusive:
/// - **Asset PDF**: provide [assetPath].
/// - **User-picked PDF**: provide [filePath] (absolute persistent on-device path).
///
/// ### Asset usage
/// ```dart
/// PdfReadingTrackerViewer(
///   pdfId: 'clean_architecture_v1',
///   pdfTitle: 'Clean Architecture',
///   assetPath: 'assets/docs/clean_architecture.pdf',
/// )
/// ```
///
/// ### User-picked PDF usage
/// ```dart
/// PdfReadingTrackerViewer(
///   pdfId: picked.pdfId,
///   pdfTitle: picked.title,
///   filePath: picked.filePath,   // always a persistent ApplicationDocuments path
/// )
/// ```
///
/// **v2.1.1 changes**
/// - Uses `_ctrl.progressPct` (which now computes `(page+1)/total`) for the
///   bottom bar so it matches the value stored in [ReadingProgress].
/// - `onViewCreated` no longer calls `notifyListeners` unnecessarily.
/// - `setState` in `_onUpdate` is guarded so overlay widgets (FAB, bottom bar)
///   only rebuild when the relevant slice of state actually changes.
class PdfReadingTrackerViewer extends StatefulWidget {
  const PdfReadingTrackerViewer({
    super.key,
    required this.pdfId,
    required this.pdfTitle,
    this.assetPath,
    this.filePath,
    this.onPageChanged,
    this.theme,
    this.swipeHorizontal = true,
    this.enableDoubleTap = true,
    this.showAppBar = true,
    this.showBottomBar = true,
    this.showBookmarkFab = true,
  }) : assert(
  (assetPath != null) != (filePath != null),
  'Provide exactly one of assetPath or filePath.',
  );

  /// Unique, stable SQLite key for this PDF. Never change after first launch.
  final String pdfId;
  final String pdfTitle;

  /// Flutter asset path. Mutually exclusive with [filePath].
  final String? assetPath;

  /// Absolute **persistent** on-device path for user-picked PDFs.
  /// Must point to a file inside ApplicationDocumentsDirectory — never a
  /// temp/cache path.  Mutually exclusive with [assetPath].
  final String? filePath;

  final void Function(int page, int total)? onPageChanged;
  final PdfViewerTheme? theme;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool showAppBar;
  final bool showBottomBar;
  final bool showBookmarkFab;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  // ---------------------------------------------------------------------------
  // Cached state snapshot — used to skip redundant setState calls (Bug 4 fix).
  // ---------------------------------------------------------------------------
  int _lastPage = -1;
  int _lastTotal = -1;
  int _lastBookmarkCount = -1;
  bool _lastSaving = false;
  bool _lastLoading = true;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfViewerController(
      pdfId: widget.pdfId,
      pdfTitle: widget.pdfTitle,
      assetPath: widget.assetPath,
      filePath: widget.filePath,
      onDeviceFilePath: widget.filePath,
    );
    _ctrl.addListener(_onUpdate);
    _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  /// Only call setState when something the UI actually cares about changed.
  ///
  /// This is the primary fix for Bug 4: programmatic jumps emit many
  /// `onPageChanged` callbacks from the renderer; without this guard every
  /// callback would trigger a full Scaffold rebuild.
  void _onUpdate() {
    if (!mounted) return;

    final pageChanged = _ctrl.currentPage != _lastPage;
    final totalChanged = _ctrl.totalPages != _lastTotal;
    final bookmarkCountChanged =
        _ctrl.bookmarks.length != _lastBookmarkCount;
    final savingChanged = _ctrl.isSavingProgress != _lastSaving;
    final loadingChanged = _ctrl.isLoading != _lastLoading;
    final errorChanged = _ctrl.error != _lastError;

    if (!pageChanged &&
        !totalChanged &&
        !bookmarkCountChanged &&
        !savingChanged &&
        !loadingChanged &&
        !errorChanged) {
      return; // nothing visible changed — skip the rebuild
    }

    _lastPage = _ctrl.currentPage;
    _lastTotal = _ctrl.totalPages;
    _lastBookmarkCount = _ctrl.bookmarks.length;
    _lastSaving = _ctrl.isSavingProgress;
    _lastLoading = _ctrl.isLoading;
    _lastError = _ctrl.error;

    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Bookmark actions
  // ---------------------------------------------------------------------------

  Future<void> _handleBookmarkTap() async {
    final note = await _showAddNoteDialog(context, _ctrl.currentPage + 1);
    if (!mounted || note == null) return;
    try {
      await _ctrl.addBookmark(note: note.isEmpty ? null : note);
    } on BookmarkServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save bookmark: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _handleBookmarksIconTap() async {
    final page = await showBookmarksSheet(
      context: context,
      bookmarks: _ctrl.bookmarks,
      currentPage: _ctrl.currentPage,
      onDelete: _ctrl.removeBookmark,
      onEditNote: _ctrl.updateBookmarkNote,
    );
    if (page != null && mounted) {
      await _ctrl.goToPage(page);
    }
  }

  // ---------------------------------------------------------------------------
  // Jump To Page
  // ---------------------------------------------------------------------------

  Future<void> _handleJumpToPage() async {
    final page = await _showJumpToPageDialog(
      context,
      currentPage: _ctrl.currentPage,
      totalPages: _ctrl.totalPages,
    );
    if (page != null && mounted) {
      await _ctrl.goToPage(page);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = widget.theme;
    final isCurrentPageBookmarked =
    _ctrl.bookmarks.any((b) => b.page == _ctrl.currentPage);

    final body = _buildBody(cs);

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
        backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
        foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        actions: [
          if (!_ctrl.isLoading && _ctrl.error == null) ...[
            IconButton(
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Jump to page',
              onPressed: _handleJumpToPage,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: _ctrl.bookmarks.isNotEmpty,
                label: Text('${_ctrl.bookmarks.length}'),
                child: const Icon(Icons.bookmarks_outlined),
              ),
              tooltip: 'View bookmarks',
              onPressed: _handleBookmarksIconTap,
            ),
          ],
        ],
      ),
      body: body,
      bottomNavigationBar:
      (!widget.showBottomBar || _ctrl.isLoading || _ctrl.error != null)
          ? null
          : ReaderBottomBar(
        currentPage: _ctrl.currentPage,
        totalPages: _ctrl.totalPages,
        // Bug 2 & 3 fix: progressPct is now computed on the
        // controller using (currentPage+1)/totalPages.
        progressPct: _ctrl.progressPct,
        isSaving: _ctrl.isSavingProgress,
      ),
      floatingActionButton:
      (!widget.showBookmarkFab || _ctrl.isLoading || _ctrl.error != null)
          ? null
          : BookmarkFab(
        isBookmarked: isCurrentPageBookmarked,
        onPressed: _handleBookmarkTap,
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_ctrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ctrl.error != null) {
      return _ErrorView(message: _ctrl.error!, onRetry: _ctrl.init);
    }

    return AlhPdfView(
      filePath: _ctrl.resolvedFilePath!,
      defaultPage: _ctrl.initialPage,
      backgroundColor: cs.surface,
      swipeHorizontal: widget.swipeHorizontal,
      enableDoubleTap: widget.enableDoubleTap,
      onViewCreated: _ctrl.onViewCreated,
      onPageChanged: (page, total) {
        _ctrl.onPageChanged(page, total);
        widget.onPageChanged?.call(page, total);
      },
      onRender: _ctrl.onRender,
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PDF error: $err'),
            backgroundColor: cs.error,
          ));
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<String?> _showAddNoteDialog(BuildContext context, int pageNumber) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bookmark page $pageNumber'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Add a note (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jump To Page dialog (free function — reusable)
// ---------------------------------------------------------------------------

/// Shows a validated "Jump to page" dialog.
///
/// Returns the **zero-based** page index to navigate to, or `null` if
/// dismissed. [currentPage] and [totalPages] are zero-based.
Future<int?> _showJumpToPageDialog(
    BuildContext context, {
      required int currentPage,
      required int totalPages,
    }) async {
  if (totalPages <= 0) return null;

  final ctrl = TextEditingController(text: '${currentPage + 1}');
  final formKey = GlobalKey<FormState>();

  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Jump to page'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Page number',
            hintText: '1 – $totalPages',
            border: const OutlineInputBorder(),
            suffixText: '/ $totalPages',
          ),
          validator: (v) {
            final n = int.tryParse(v?.trim() ?? '');
            if (n == null) return 'Enter a number';
            if (n < 1 || n > totalPages) return '1 – $totalPages';
            return null;
          },
          onFieldSubmitted: (_) {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(int.parse(ctrl.text.trim()) - 1);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(int.parse(ctrl.text.trim()) - 1);
            }
          },
          child: const Text('Go'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: cs.error),
            const SizedBox(height: 16),
            Text('Could not load PDF',
                style: tt.titleMedium?.copyWith(color: cs.error)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}