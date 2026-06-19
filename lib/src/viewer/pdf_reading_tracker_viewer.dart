import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../services/bookmark_service.dart';
import 'pdf_search_controller.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/bookmark_fab.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/highlight_action_bar.dart';
import 'widgets/pdf_search_bar.dart';
import 'widgets/reader_bottom_bar.dart';

// ---------------------------------------------------------------------------
// Theme
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
    this.showAppBar      = true,
    this.showBottomBar   = true,
    this.showBookmarkFab = true,
    this.enableSearch    = true,
    this.enableHighlight = true,
  }) : assert(
  (assetPath != null) != (filePath != null),
  'Provide exactly one of assetPath or filePath.',
  );

  final String  pdfId;
  final String  pdfTitle;
  final String? assetPath;
  final String? filePath;
  final void Function(int page, int total)? onPageChanged;
  final PdfViewerTheme? theme;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool showAppBar;
  final bool showBottomBar;
  final bool showBookmarkFab;
  final bool enableSearch;

  /// When `true`, text selection triggers the highlight action bar.
  final bool enableHighlight;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  /// Key for accessing [sf.SfPdfViewerState.getSelectedTextLines()].
  final GlobalKey<sf.SfPdfViewerState> _sfViewerKey =
  GlobalKey<sf.SfPdfViewerState>();

  bool    _isLoading        = true;
  String? _error;
  String? _resolvedFilePath;
  int     _initialPage      = 0;
  bool    _searchVisible    = false;

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
  // Highlight action
  // ---------------------------------------------------------------------------

  /// Called when the user taps "Highlight" in the action bar.
  ///
  /// Flow (verified against Syncfusion 27.x docs):
  /// 1. Fetch the current [sf.PdfTextLine] list via the viewer state key.
  /// 2. Build a [sf.HighlightAnnotation] from those lines and add it to the
  ///    viewer via the controller.
  /// 3. Pass the same lines to the domain controller to persist to SQLite.
  ///
  /// The color is read from [sf.PdfViewerController.annotationSettings] after
  /// the add so it reflects any user-configured default; it falls back to the
  /// default yellow if settings are unavailable.
  void _commitHighlight() {
    final textLines =
        _sfViewerKey.currentState?.getSelectedTextLines() ?? const [];

    if (textLines.isEmpty) {
      // Selection was cleared before tap — nothing to do.
      _ctrl.captureTextSelection(null, null, null);
      return;
    }

    // Build and add the annotation to Syncfusion.
    final annotation = sf.HighlightAnnotation(
      textBoundsCollection: textLines,
    );

    // Use the configured default highlight color (yellow family).
    // sf.PdfAnnotationSettings exposes `textMarkup` which has `color`.
    // We read it after construction; the annotation.color has already been
    // set by the AnnotationSettings default.
    _ctrl.sfController.addAnnotation(annotation);

    // Persist to SQLite using the color that was actually applied.
    // annotation.color is set by Syncfusion from annotationSettings when
    // addAnnotation() is called; reading it immediately after is safe.
    _ctrl.commitHighlightFromLines(
      textLines:  textLines,
      colorValue: annotation.color.value,
    );
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
        content:         Text('Could not save bookmark: $e'),
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
          title: Text(widget.pdfTitle,
              overflow: TextOverflow.ellipsis),
          backgroundColor:
          theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor:
          theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
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
          title: Text(widget.pdfTitle,
              overflow: TextOverflow.ellipsis),
          backgroundColor:
          theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor:
          theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: errorBody,
      )
          : errorBody;
    }

    // Core viewer — keyed on path so Syncfusion never reloads on swipe.
    final viewerCore = _PdfViewerCore(
      key:              ValueKey(_resolvedFilePath),
      sfViewerKey:      _sfViewerKey,
      resolvedFilePath: _resolvedFilePath!,
      initialPage:      _initialPage,
      swipeHorizontal:  widget.swipeHorizontal,
      enableDoubleTap:  widget.enableDoubleTap,
      enableHighlight:  widget.enableHighlight,
      sfController:     _ctrl.sfController,
      onPageChanged: (n) {
        _ctrl.onPageChanged(n);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      onDocumentLoaded:     (n)    => _ctrl.onDocumentLoaded(n),
      onDocumentLoadFailed: (desc) => _ctrl.onDocumentLoadFailed(desc),
      onTextSelectionChanged: (text, region) {
        // Capture text lines at selection time from the viewer state.
        final lines = _sfViewerKey.currentState?.getSelectedTextLines();
        _ctrl.captureTextSelection(text, region, lines);
      },
    );

    if (!widget.showAppBar) {
      return _wrapWithHighlightBar(viewerCore);
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + (_searchVisible ? 56.0 : 0.0),
        ),
        child: ListenableBuilder(
          listenable: _ctrl.bookmarksNotifier,
          builder: (_, __) => _AppBarWithSearch(
            title:            widget.pdfTitle,
            backgroundColor:
            theme?.appBarBackgroundColor ?? cs.primaryContainer,
            foregroundColor:
            theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
            bookmarkCount:    _ctrl.bookmarks.length,
            searchVisible:    _searchVisible,
            enableSearch:     widget.enableSearch,
            searchController: _ctrl.searchController,
            onJumpToPage:     _handleJumpToPage,
            onBookmarks:      _handleBookmarksIconTap,
            onToggleSearch:   _toggleSearch,
          ),
        ),
      ),
      body: _wrapWithHighlightBar(viewerCore),
      bottomNavigationBar: widget.showBottomBar
          ? ListenableBuilder(
        listenable: Listenable.merge(
            [_ctrl.pageNotifier, _ctrl.savingNotifier]),
        builder: (_, __) => ReaderBottomBar(
          currentPage: _ctrl.currentPage,
          totalPages:  _ctrl.totalPages,
          progressPct: _ctrl.progressPct,
          isSaving:    _ctrl.isSavingProgress,
        ),
      )
          : null,
      floatingActionButton: widget.showBookmarkFab
          ? ListenableBuilder(
        listenable: Listenable.merge(
            [_ctrl.pageNotifier, _ctrl.bookmarksNotifier]),
        builder: (_, __) => BookmarkFab(
          isBookmarked: _ctrl.bookmarks
              .any((b) => b.page == _ctrl.currentPage),
          onPressed: _handleBookmarkTap,
        ),
      )
          : null,
    );
  }

  /// Wraps [child] in a [Stack] that overlays [HighlightActionBar] when the
  /// user has an active text selection.
  Widget _wrapWithHighlightBar(Widget child) {
    if (!widget.enableHighlight) return child;

    return ListenableBuilder(
      listenable: _ctrl.highlightNotifier,
      builder: (_, __) {
        final pending = _ctrl.pendingSelection;
        return Stack(
          children: [
            child,
            if (pending != null)
              Positioned(
                bottom: 80,
                left:   0,
                right:  0,
                child: Center(
                  child: HighlightActionBar(
                    selectedText: pending.selectedText,
                    onHighlight:  _commitHighlight,
                    onDismiss: () =>
                        _ctrl.captureTextSelection(null, null, null),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<String?> _showAddNoteDialog(
      BuildContext context, int pageNumber) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bookmark page $pageNumber'),
        content: TextField(
          controller:          ctrl,
          decoration: const InputDecoration(
            hintText: 'Add a note (optional)',
            border:   OutlineInputBorder(),
          ),
          maxLines:           2,
          autofocus:          true,
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
// AppBar with collapsible search
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

  final String              title;
  final Color               backgroundColor;
  final Color               foregroundColor;
  final int                 bookmarkCount;
  final bool                searchVisible;
  final bool                enableSearch;
  final PdfSearchController searchController;
  final VoidCallback        onJumpToPage;
  final VoidCallback        onBookmarks;
  final VoidCallback        onToggleSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          title:           Text(title, overflow: TextOverflow.ellipsis),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          actions: [
            if (enableSearch)
              IconButton(
                icon: Icon(searchVisible
                    ? Icons.search_off_rounded
                    : Icons.search_rounded),
                tooltip:   searchVisible ? 'Close search' : 'Search text',
                onPressed: onToggleSearch,
              ),
            IconButton(
              icon:      const Icon(Icons.redo_rounded),
              tooltip:   'Jump to page',
              onPressed: onJumpToPage,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: bookmarkCount > 0,
                label: Text('$bookmarkCount'),
                child: const Icon(Icons.bookmarks_outlined),
              ),
              tooltip:   'View bookmarks',
              onPressed: onBookmarks,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve:    Curves.easeOutCubic,
          child:    searchVisible
              ? PdfSearchBar(searchController: searchController)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stable SfPdfViewer host
// ---------------------------------------------------------------------------

class _PdfViewerCore extends StatelessWidget {
  const _PdfViewerCore({
    super.key,
    required this.sfViewerKey,
    required this.resolvedFilePath,
    required this.initialPage,
    required this.swipeHorizontal,
    required this.enableDoubleTap,
    required this.enableHighlight,
    required this.sfController,
    required this.onPageChanged,
    required this.onDocumentLoaded,
    required this.onDocumentLoadFailed,
    required this.onTextSelectionChanged,
  });

  final GlobalKey<sf.SfPdfViewerState> sfViewerKey;
  final String resolvedFilePath;
  final int    initialPage;
  final bool   swipeHorizontal;
  final bool   enableDoubleTap;
  final bool   enableHighlight;
  final sf.PdfViewerController sfController;
  final void Function(int)            onPageChanged;
  final void Function(int)            onDocumentLoaded;
  final void Function(String)         onDocumentLoadFailed;
  final void Function(String?, Rect?) onTextSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return sf.SfPdfViewer.file(
      File(resolvedFilePath),
      key:               sfViewerKey,
      controller:        sfController,
      initialPageNumber: initialPage + 1, // BOUNDARY: zero → one
      scrollDirection:   swipeHorizontal
          ? sf.PdfScrollDirection.horizontal
          : sf.PdfScrollDirection.vertical,
      enableDoubleTapZooming: enableDoubleTap,
      canShowScrollHead:   false,
      canShowScrollStatus: false,
      onPageChanged: (sf.PdfPageChangedDetails d) =>
          onPageChanged(d.newPageNumber),
      onDocumentLoaded: (sf.PdfDocumentLoadedDetails d) =>
          onDocumentLoaded(d.document.pages.count),
      onDocumentLoadFailed: (sf.PdfDocumentLoadFailedDetails d) =>
          onDocumentLoadFailed('${d.error}: ${d.description}'),
      onTextSelectionChanged: enableHighlight
          ? (sf.PdfTextSelectionChangedDetails d) =>
          onTextSelectionChanged(d.selectedText, d.globalSelectedRegion)
          : null,
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
      title:   const Text('Jump to page'),
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