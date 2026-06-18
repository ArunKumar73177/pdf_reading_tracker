import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../services/bookmark_service.dart';
import 'pdf_search_controller.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/bookmark_fab.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/pdf_search_bar.dart';
import 'widgets/reader_bottom_bar.dart';

// ---------------------------------------------------------------------------
// Theme data-class (public API — unchanged)
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
    this.enableSearch = true,
  }) : assert(
  (assetPath != null) != (filePath != null),
  'Provide exactly one of assetPath or filePath.',
  );

  final String pdfId;
  final String pdfTitle;
  final String? assetPath;
  final String? filePath;
  final void Function(int page, int total)? onPageChanged;
  final PdfViewerTheme? theme;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool showAppBar;
  final bool showBottomBar;
  final bool showBookmarkFab;

  /// Set to `false` to hide the search button in the app bar.
  final bool enableSearch;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  // Only loading/error/path transitions drive a full setState.
  // Page, bookmark, saving, and search updates are handled by scoped
  // ListenableBuilder sub-trees so the Scaffold is never rebuilt on swipe.
  bool    _isLoading        = true;
  String? _error;
  String? _resolvedFilePath;
  int     _initialPage      = 0;

  // Search bar visibility — local UI state only, no rebuild cascade.
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfViewerController(
      pdfId:            widget.pdfId,
      pdfTitle:         widget.pdfTitle,
      assetPath:        widget.assetPath,
      filePath:         widget.filePath,
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

  // Fires only for loading / error / path state — never for page swipes.
  void _onUpdate() {
    if (!mounted) return;

    final loadingChanged = _ctrl.isLoading       != _isLoading;
    final errorChanged   = _ctrl.error           != _error;
    final pathChanged    = _ctrl.resolvedFilePath != _resolvedFilePath;

    if (!loadingChanged && !errorChanged && !pathChanged) return;

    setState(() {
      _isLoading        = _ctrl.isLoading;
      _error            = _ctrl.error;
      _resolvedFilePath = _ctrl.resolvedFilePath;
      _initialPage      = _ctrl.initialPage;
    });
  }

  // ---------------------------------------------------------------------------
  // Handlers
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
      context:     context,
      bookmarks:   _ctrl.bookmarks,
      currentPage: _ctrl.currentPage,
      onDelete:    _ctrl.removeBookmark,
      onEditNote:  _ctrl.updateBookmarkNote,
    );
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  Future<void> _handleJumpToPage() async {
    final page = await _showJumpToPageDialog(
      context,
      currentPage: _ctrl.currentPage,
      totalPages:  _ctrl.totalPages,
    );
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _ctrl.searchController.clearSearch();
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final theme = widget.theme;

    if (_isLoading) {
      return widget.showAppBar
          ? Scaffold(
        appBar: AppBar(
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
          backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: const Center(child: CircularProgressIndicator()),
      )
          : const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final errorBody = _ErrorView(message: _error!, onRetry: _ctrl.init);
      return widget.showAppBar
          ? Scaffold(
        appBar: AppBar(
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
          backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: errorBody,
      )
          : errorBody;
    }

    // Normal reading state — Scaffold built ONCE. Page swipes, search state,
    // bookmarks, and highlights all update through scoped ListenableBuilders.
    final viewerCore = _PdfViewerCore(
      key:              ValueKey(_resolvedFilePath),
      resolvedFilePath: _resolvedFilePath!,
      initialPage:      _initialPage,
      swipeHorizontal:  widget.swipeHorizontal,
      enableDoubleTap:  widget.enableDoubleTap,
      sfController:     _ctrl.sfController,
      onPageChanged: (newPageNumber) {
        _ctrl.onPageChanged(newPageNumber);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      onDocumentLoaded:     (pageCount) => _ctrl.onDocumentLoaded(pageCount),
      onDocumentLoadFailed: (desc)      => _ctrl.onDocumentLoadFailed(desc),
    );

    if (!widget.showAppBar) return viewerCore;

    return Scaffold(
      // ── AppBar — rebuilt only when bookmark list changes ──────────────────
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + (_searchVisible ? 56.0 : 0.0),
        ),
        child: ListenableBuilder(
          listenable: _ctrl.bookmarksNotifier,
          builder: (context, _) => _AppBarWithSearch(
            title:           widget.pdfTitle,
            backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
            foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
            bookmarkCount:   _ctrl.bookmarks.length,
            searchVisible:   _searchVisible,
            enableSearch:    widget.enableSearch,
            searchController: _ctrl.searchController,
            onJumpToPage:    _handleJumpToPage,
            onBookmarks:     _handleBookmarksIconTap,
            onToggleSearch:  _toggleSearch,
          ),
        ),
      ),

      body: viewerCore,

      // ── Bottom bar — page + saving ────────────────────────────────────────
      bottomNavigationBar: widget.showBottomBar
          ? ListenableBuilder(
        listenable: Listenable.merge(
            [_ctrl.pageNotifier, _ctrl.savingNotifier]),
        builder: (context, _) => ReaderBottomBar(
          currentPage: _ctrl.currentPage,
          totalPages:  _ctrl.totalPages,
          progressPct: _ctrl.progressPct,
          isSaving:    _ctrl.isSavingProgress,
        ),
      )
          : null,

      // ── FAB — page + bookmark list ────────────────────────────────────────
      floatingActionButton: widget.showBookmarkFab
          ? ListenableBuilder(
        listenable: Listenable.merge(
            [_ctrl.pageNotifier, _ctrl.bookmarksNotifier]),
        builder: (context, _) => BookmarkFab(
          isBookmarked: _ctrl.bookmarks
              .any((b) => b.page == _ctrl.currentPage),
          onPressed: _handleBookmarkTap,
        ),
      )
          : null,
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
// AppBar with collapsible search bar
// ---------------------------------------------------------------------------

class _AppBarWithSearch extends StatelessWidget {
  const _AppBarWithSearch({
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.bookmarkCount,
    required this.searchVisible,
    required this.enableSearch,
    required this.searchController,
    required this.onJumpToPage,
    required this.onBookmarks,
    required this.onToggleSearch,
  });

  final String title;
  final Color  backgroundColor;
  final Color  foregroundColor;
  final int    bookmarkCount;
  final bool   searchVisible;
  final bool   enableSearch;
  final PdfSearchController searchController;
  final VoidCallback onJumpToPage;
  final VoidCallback onBookmarks;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          actions: [
            if (enableSearch)
              IconButton(
                icon: Icon(searchVisible
                    ? Icons.search_off_rounded
                    : Icons.search_rounded),
                tooltip: searchVisible ? 'Close search' : 'Search text',
                onPressed: onToggleSearch,
              ),
            IconButton(
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Jump to page',
              onPressed: onJumpToPage,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: bookmarkCount > 0,
                label: Text('$bookmarkCount'),
                child: const Icon(Icons.bookmarks_outlined),
              ),
              tooltip: 'View bookmarks',
              onPressed: onBookmarks,
            ),
          ],
        ),
        // Animated search bar — slides in/out without rebuilding the Scaffold.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: searchVisible
              ? PdfSearchBar(searchController: searchController)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stable SfPdfViewer host
//
// Keyed on resolvedFilePath — never rebuilt by page-change notifications.
// Syncfusion therefore never reloads the document during a swipe.
//
// Scroll-head and scroll-status overlays disabled (Fix 8 — preserved):
// they repaint on every scroll frame and add paint/compositing cost.
// ---------------------------------------------------------------------------

class _PdfViewerCore extends StatelessWidget {
  const _PdfViewerCore({
    super.key,
    required this.resolvedFilePath,
    required this.initialPage,
    required this.swipeHorizontal,
    required this.enableDoubleTap,
    required this.sfController,
    required this.onPageChanged,
    required this.onDocumentLoaded,
    required this.onDocumentLoadFailed,
  });

  final String resolvedFilePath;
  final int    initialPage;
  final bool   swipeHorizontal;
  final bool   enableDoubleTap;
  final sf.PdfViewerController sfController;
  final void Function(int newPageNumber)  onPageChanged;
  final void Function(int pageCount)      onDocumentLoaded;
  final void Function(String description) onDocumentLoadFailed;

  @override
  Widget build(BuildContext context) {
    return sf.SfPdfViewer.file(
      File(resolvedFilePath),
      controller:        sfController,
      initialPageNumber: initialPage + 1, // Syncfusion boundary: +1
      scrollDirection:   swipeHorizontal
          ? sf.PdfScrollDirection.horizontal
          : sf.PdfScrollDirection.vertical,
      enableDoubleTapZooming: enableDoubleTap,
      // Disable per-frame scroll overlays — reduces compositor layer count.
      canShowScrollHead:   false,
      canShowScrollStatus: false,
      onPageChanged: (sf.PdfPageChangedDetails details) =>
          onPageChanged(details.newPageNumber),
      onDocumentLoaded: (sf.PdfDocumentLoadedDetails details) =>
          onDocumentLoaded(details.document.pages.count),
      onDocumentLoadFailed: (sf.PdfDocumentLoadFailedDetails details) =>
          onDocumentLoadFailed('${details.error}: ${details.description}'),
    );
  }
}

// ---------------------------------------------------------------------------
// Jump-to-page dialog
// ---------------------------------------------------------------------------

Future<int?> _showJumpToPageDialog(
    BuildContext context, {
      required int currentPage,
      required int totalPages,
    }) async {
  if (totalPages <= 0) return null;

  final ctrl    = TextEditingController(text: '${currentPage + 1}');
  final formKey = GlobalKey<FormState>();

  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Jump to page'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller:   ctrl,
          keyboardType: TextInputType.number,
          autofocus:    true,
          decoration:   InputDecoration(
            labelText:  'Page number',
            hintText:   '1 – $totalPages',
            border:     const OutlineInputBorder(),
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
  final String       message;
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
              icon:  const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}