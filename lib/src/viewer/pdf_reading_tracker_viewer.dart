import 'package:alh_pdf_view/alh_pdf_view.dart';
import 'package:flutter/material.dart';
import '../services/bookmark_service.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/bookmark_fab.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/reader_bottom_bar.dart';

// ---------------------------------------------------------------------------
// Theme data-class
// ---------------------------------------------------------------------------

/// Optional theming for [PdfReadingTrackerViewer].
///
/// Pass a [PdfViewerTheme] to [PdfReadingTrackerViewer.theme] to override
/// specific colours without replacing the entire app theme.
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
/// Drop it anywhere in your widget tree. The widget handles:
///  - rendering the PDF via `alh_pdf_view`
///  - auto-saving & restoring reading progress (last page)
///  - adding, loading, and removing bookmarks
///  - displaying a bottom progress bar and a bookmark FAB
///
/// ### Minimal usage
/// ```dart
/// PdfReadingTrackerViewer(
///   pdfId: 'clean_architecture_v1',
///   pdfTitle: 'Clean Architecture',
///   assetPath: 'assets/docs/clean_architecture.pdf',
/// )
/// ```
///
/// ### With optional callbacks and theming
/// ```dart
/// PdfReadingTrackerViewer(
///   pdfId: 'clean_architecture_v1',
///   pdfTitle: 'Clean Architecture',
///   assetPath: 'assets/docs/clean_architecture.pdf',
///   onPageChanged: (page, total) => print('$page / $total'),
///   theme: PdfViewerTheme(
///     appBarBackgroundColor: Colors.indigo,
///     appBarForegroundColor: Colors.white,
///   ),
/// )
/// ```
///
/// The [pdfId] must be unique and stable across app launches — it is the
/// primary key used to look up progress and bookmarks in SQLite.
class PdfReadingTrackerViewer extends StatefulWidget {
  const PdfReadingTrackerViewer({
    super.key,
    required this.pdfId,
    required this.pdfTitle,
    required this.assetPath,
    this.onPageChanged,
    this.theme,
    this.swipeHorizontal = true,
    this.enableDoubleTap = true,
    this.showAppBar = true,
    this.showBottomBar = true,
    this.showBookmarkFab = true,
  });

  /// Unique, stable key for this PDF document.
  ///
  /// Used as the SQLite primary key — **do not change it** after first launch
  /// or progress / bookmarks will be lost.
  final String pdfId;

  /// Human-readable title shown in the [AppBar].
  final String pdfTitle;

  /// Flutter asset path, e.g. `'assets/docs/sample.pdf'`.
  final String assetPath;

  /// Called on every page turn with the new zero-based page index and total.
  final void Function(int page, int total)? onPageChanged;

  /// Optional theme overrides (app bar colours, progress bar colour).
  final PdfViewerTheme? theme;

  /// Orientation of page swiping. Defaults to horizontal.
  final bool swipeHorizontal;

  /// Enable double-tap to zoom.
  final bool enableDoubleTap;

  /// Whether to show the built-in [AppBar].
  ///
  /// Set to `false` when embedding the viewer inside your own [Scaffold].
  final bool showAppBar;

  /// Whether to show the [ReaderBottomBar].
  final bool showBottomBar;

  /// Whether to show the bookmark [FloatingActionButton].
  final bool showBookmarkFab;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfViewerController(
      pdfId: widget.pdfId,
      pdfTitle: widget.pdfTitle,
      assetPath: widget.assetPath,
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

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleBookmarkTap() async {
    final note = await _showNoteDialog(context, _ctrl.currentPage + 1);
    if (!mounted || note == null) return;

    try {
      await _ctrl.addBookmark(note: note.isEmpty ? null : note);
    } on BookmarkServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save bookmark: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleBookmarksIconTap() async {
    final page = await showBookmarksSheet(
      context: context,
      bookmarks: _ctrl.bookmarks,
      currentPage: _ctrl.currentPage,
      onDelete: _ctrl.removeBookmark,
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

    if (!widget.showAppBar) {
      // Embedding mode — caller owns the Scaffold.
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
        backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
        foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        actions: [
          if (!_ctrl.isLoading && _ctrl.error == null)
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
      ),
      body: body,
      bottomNavigationBar:
      (!widget.showBottomBar || _ctrl.isLoading || _ctrl.error != null)
          ? null
          : ReaderBottomBar(
        currentPage: _ctrl.currentPage,
        totalPages: _ctrl.totalPages,
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
      return _ErrorView(
        message: _ctrl.error!,
        onRetry: _ctrl.init,
      );
    }

    return AlhPdfView(
      filePath: _ctrl.filePath!,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF error: $err'),
              backgroundColor: cs.error,
            ),
          );
        }
      },
    );
  }

  Future<String?> _showNoteDialog(BuildContext context, int pageNumber) {
    final textCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bookmark page $pageNumber'),
        content: TextField(
          controller: textCtrl,
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
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view (internal)
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