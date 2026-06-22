import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../models/note.dart';
import '../services/bookmark_service.dart';
import 'pdf_search_controller.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/annotation_action_bar.dart';
import 'widgets/bookmark_fab.dart';
import 'widgets/bookmarks_sheet.dart';
import 'widgets/highlights_sheet.dart';
import 'widgets/notes_sheet.dart';
import 'widgets/pdf_search_bar.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/safe_note_dialog.dart';

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
// PdfReadingTrackerViewer
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
    this.swipeHorizontal = false,
    this.enableDoubleTap = true,
    this.showAppBar = true,
    this.showBottomBar = true,
    this.showBookmarkFab = true,
    this.enableSearch = true,
    this.enableHighlight = true,
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
  final bool enableSearch;
  final bool enableHighlight;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  final GlobalKey<sf.SfPdfViewerState> _sfViewerKey =
  GlobalKey<sf.SfPdfViewerState>();

  bool _isLoading = true;
  String? _error;
  String? _resolvedFilePath;
  int _initialPage = 0;
  bool _searchVisible = false;

  String? _pendingAnnotationNote;
  bool _dialogOpen = false;

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
    _ctrl.addListener(_onControllerUpdate);
    _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_ctrl.isLoading == _isLoading &&
        _ctrl.error == _error &&
        _ctrl.resolvedFilePath == _resolvedFilePath) return;
    setState(() {
      _isLoading = _ctrl.isLoading;
      _error = _ctrl.error;
      _resolvedFilePath = _ctrl.resolvedFilePath;
      _initialPage = _ctrl.initialPage;
    });
  }

  // -------------------------------------------------------------------------
  // Annotation commit
  // -------------------------------------------------------------------------

  void _commitAnnotation(AnnotationCommit commit) {
    final textLines =
        _sfViewerKey.currentState?.getSelectedTextLines() ?? const [];
    if (textLines.isEmpty) {
      _ctrl.captureTextSelection(null, null, null);
      return;
    }
    _ctrl.commitAnnotation(textLines: textLines, commit: commit);
    if (mounted) setState(() => _pendingAnnotationNote = null);
  }

  Future<void> _openPendingAnnotationNoteDialog() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final result = await showSafeNoteDialog(
        context: context,
        title: 'Add note',
        initialText: _pendingAnnotationNote ?? '',
        allowDelete: _pendingAnnotationNote != null,
      );
      if (result == null || !mounted) return;
      setState(() {
        _pendingAnnotationNote = result.deleted ? null : result.text;
      });
    } finally {
      _dialogOpen = false;
    }
  }

  // -------------------------------------------------------------------------
  // Notes
  // -------------------------------------------------------------------------

  /// Handles the "Add Note" FAB tap.
  ///
  /// ### Issue 1 fix — snapshot-based selection read
  ///
  /// When the user taps the note FAB, `SfPdfViewer` fires a deselection
  /// event (`onTextSelectionChanged(null, null)`) before this method runs,
  /// which would clear `_ctrl.pendingSelection`. We instead read
  /// `_ctrl.snapshotSelection`, which is preserved through deselection
  /// events and is only cleared after a note is saved or an annotation is
  /// committed.
  ///
  /// After reading, `_ctrl.clearSnapshot()` is called inside the `finally`
  /// block so the snapshot is consumed exactly once.
  Future<void> _handleAddNoteTap() async {
    if (_dialogOpen) return;
    _dialogOpen = true;

    // Read the stable snapshot — not pendingSelection (which may be null
    // because the viewer just fired a deselection event on FAB touch-down).
    final snapshot = _ctrl.snapshotSelection;
    final capturedText = snapshot?.selectedText ?? '';
    final capturedRects = snapshot?.textLines
        .map((l) => NoteRect(
      left: l.bounds.left,
      top: l.bounds.top,
      right: l.bounds.right,
      bottom: l.bounds.bottom,
    ))
        .toList(growable: false) ??
        const <NoteRect>[];

    try {
      final result = await showSafeNoteDialog(
        context: context,
        title: capturedText.isNotEmpty
            ? 'Note for: "${capturedText.length > 40 ? '${capturedText.substring(0, 40)}…' : capturedText}"'
            : 'Add note — Page ${_ctrl.currentPage + 1}',
        initialText: '',
        allowDelete: false,
        onOpen: _ctrl.clearPdfSelection,
      );
      if (result == null || result.deleted || !mounted) return;
      if (result.text.trim().isEmpty) return;
      await _ctrl.addNote(
        noteText: result.text.trim(),
        selectedText: capturedText,
        rectList: capturedRects,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save note: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      // Always clear the snapshot — consumed or cancelled.
      _ctrl.clearSnapshot();
      _dialogOpen = false;
    }
  }

  Future<void> _handleNotesIconTap() async {
    final page = await showNotesSheet(
      context: context,
      notes: _ctrl.notes,
      currentPage: _ctrl.currentPage,
      onDelete: _ctrl.removeNote,
      onEdit: _ctrl.updateNote,
    );
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  // -------------------------------------------------------------------------
  // Bookmarks
  // -------------------------------------------------------------------------

  Future<void> _handleBookmarkTap() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final result = await showSafeNoteDialog(
        context: context,
        title: 'Bookmark page ${_ctrl.currentPage + 1}',
        initialText: '',
        allowDelete: false,
        onOpen: _ctrl.clearPdfSelection,
      );
      if (result == null || !mounted) return;
      final note = result.deleted ? null : result.text.trim();
      await _ctrl.addBookmark(
          note: (note == null || note.isEmpty) ? null : note);
    } on BookmarkServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save bookmark: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      _dialogOpen = false;
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
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  Future<void> _handleHighlightsIconTap() async {
    final page = await showHighlightsSheet(
      context: context,
      highlights: _ctrl.highlights,
      currentPage: _ctrl.currentPage,
      onDelete: _ctrl.removeHighlight,
      onEditNote: _ctrl.updateHighlightNote,
    );
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  Future<void> _handleJumpToPage() async {
    final page = await _showJumpToPageDialog(
      context,
      currentPage: _ctrl.currentPage,
      totalPages: _ctrl.totalPages,
    );
    if (page != null && mounted) await _ctrl.goToPage(page);
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _ctrl.searchController.clearSearch();
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = widget.theme;

    if (_isLoading) {
      return widget.showAppBar
          ? Scaffold(
        appBar: AppBar(
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
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
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
          backgroundColor:
          theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor:
          theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: errorBody,
      )
          : errorBody;
    }

    final viewerCore = _PdfViewerCore(
      key: ValueKey(_resolvedFilePath),
      sfViewerKey: _sfViewerKey,
      resolvedFilePath: _resolvedFilePath!,
      initialPage: _initialPage,
      swipeHorizontal: widget.swipeHorizontal,
      enableDoubleTap: widget.enableDoubleTap,
      enableHighlight: widget.enableHighlight,
      sfController: _ctrl.sfController,
      onPageChanged: (n) {
        _ctrl.onPageChanged(n);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      // Issue 3 fix: pass ScrollMetrics so the controller can use
      // pixels + maxScrollExtent for page detection.
      onScrollUpdate: (metrics) {
        _ctrl.onScrollUpdate(metrics);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      onDocumentLoaded: _ctrl.onDocumentLoaded,
      onDocumentLoadFailed: _ctrl.onDocumentLoadFailed,
      onTextSelectionChanged: (text, region) {
        if (_dialogOpen) return;
        final lines = _sfViewerKey.currentState?.getSelectedTextLines();
        _ctrl.captureTextSelection(text, region, lines);
      },
    );

    final body = _buildOverlayStack(viewerCore);

    if (!widget.showAppBar) return body;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
            kToolbarHeight + (_searchVisible ? 56.0 : 0.0)),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _ctrl.bookmarksNotifier,
            _ctrl.highlightNotifier,
            _ctrl.notesNotifier,
          ]),
          builder: (_, __) => _AppBarWithSearch(
            title: widget.pdfTitle,
            backgroundColor:
            theme?.appBarBackgroundColor ?? cs.primaryContainer,
            foregroundColor:
            theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
            bookmarkCount: _ctrl.bookmarks.length,
            highlightCount: _ctrl.highlights.length,
            noteCount: _ctrl.notes.length,
            searchVisible: _searchVisible,
            enableSearch: widget.enableSearch,
            searchController: _ctrl.searchController,
            onJumpToPage: _handleJumpToPage,
            onBookmarks: _handleBookmarksIconTap,
            onHighlights: _handleHighlightsIconTap,
            onNotes: _handleNotesIconTap,
            onToggleSearch: _toggleSearch,
          ),
        ),
      ),
      body: body,
      floatingActionButton: widget.showBookmarkFab
          ? ListenableBuilder(
        listenable: Listenable.merge(
            [_ctrl.pageNotifier, _ctrl.bookmarksNotifier]),
        builder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'addNoteFab',
              tooltip: 'Add note',
              onPressed: _handleAddNoteTap,
              child: const Icon(Icons.note_add_outlined),
            ),
            const SizedBox(height: 12),
            BookmarkFab(
              isBookmarked: _ctrl.bookmarks
                  .any((b) => b.page == _ctrl.currentPage),
              onPressed: _handleBookmarkTap,
            ),
          ],
        ),
      )
          : null,
    );
  }

  // -------------------------------------------------------------------------
  // Overlay stack
  // -------------------------------------------------------------------------

  Widget _buildOverlayStack(Widget child) {
    return Stack(
      children: [
        child,

        ListenableBuilder(
          listenable: _ctrl.highlightNotifier,
          builder: (context, __) {
            final pending = _ctrl.pendingSelection;

            if (pending == null && _pendingAnnotationNote != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _pendingAnnotationNote = null);
              });
            }

            return Positioned(
              bottom: 72,
              left: 12,
              right: 12,
              child: (widget.enableHighlight && pending != null)
                  ? AnnotationActionBar(
                key: const ValueKey('annotation_action_bar'),
                selectedText: pending.selectedText,
                currentNote: _pendingAnnotationNote,
                onCommit: _commitAnnotation,
                onDismiss: () {
                  if (mounted) {
                    setState(() => _pendingAnnotationNote = null);
                  }
                  _ctrl.captureTextSelection(null, null, null);
                  _ctrl.clearSnapshot();
                },
                onAddNote: _openPendingAnnotationNoteDialog,
              )
                  : const SizedBox.shrink(),
            );
          },
        ),

        if (widget.showBottomBar)
          ListenableBuilder(
            listenable: Listenable.merge([
              _ctrl.pageNotifier,
              _ctrl.savingNotifier,
              _ctrl.notesNotifier,
            ]),
            builder: (_, __) => ReaderProgressOverlay(
              currentPage: _ctrl.currentPage,
              totalPages: _ctrl.totalPages,
              progressPct: _ctrl.progressPct,
              isSaving: _ctrl.isSavingProgress,
              noteCountOnCurrentPage: _ctrl.noteCountOnCurrentPage,
            ),
          ),
      ],
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
    required this.highlightCount,
    required this.noteCount,
    required this.searchVisible,
    required this.enableSearch,
    required this.searchController,
    required this.onJumpToPage,
    required this.onBookmarks,
    required this.onHighlights,
    required this.onNotes,
    required this.onToggleSearch,
  });

  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final int bookmarkCount;
  final int highlightCount;
  final int noteCount;
  final bool searchVisible;
  final bool enableSearch;
  final PdfSearchController searchController;
  final VoidCallback onJumpToPage;
  final VoidCallback onBookmarks;
  final VoidCallback onHighlights;
  final VoidCallback onNotes;
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
                isLabelVisible: noteCount > 0,
                label: Text('$noteCount'),
                child: const Icon(Icons.sticky_note_2_outlined),
              ),
              tooltip: 'View notes',
              onPressed: onNotes,
            ),
            IconButton(
              icon: Badge(
                isLabelVisible: highlightCount > 0,
                label: Text('$highlightCount'),
                child: const Icon(Icons.format_color_text_rounded),
              ),
              tooltip: 'View annotations',
              onPressed: onHighlights,
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
// _PdfViewerCore
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
    required this.onScrollUpdate,
    required this.onDocumentLoaded,
    required this.onDocumentLoadFailed,
    required this.onTextSelectionChanged,
  });

  final GlobalKey<sf.SfPdfViewerState> sfViewerKey;
  final String resolvedFilePath;
  final int initialPage;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool enableHighlight;
  final sf.PdfViewerController sfController;
  final void Function(int) onPageChanged;

  /// Issue 3 fix: receives [ScrollMetrics] so the controller can use
  /// `pixels` and `maxScrollExtent` for scroll-extent-based page detection.
  final void Function(ScrollMetrics metrics) onScrollUpdate;

  final void Function(int) onDocumentLoaded;
  final void Function(String) onDocumentLoadFailed;
  final void Function(String?, Rect?) onTextSelectionChanged;

  static const double _kPageSpacing = 12.0;

  @override
  Widget build(BuildContext context) {
    final viewer = sf.SfPdfViewer.file(
      File(resolvedFilePath),
      key: sfViewerKey,
      controller: sfController,
      initialPageNumber: initialPage + 1,
      pageLayoutMode: sf.PdfPageLayoutMode.continuous,
      pageSpacing: swipeHorizontal ? 0 : _kPageSpacing,
      scrollDirection: swipeHorizontal
          ? sf.PdfScrollDirection.horizontal
          : sf.PdfScrollDirection.vertical,
      enableDoubleTapZooming: enableDoubleTap,
      canShowScrollHead: false,
      canShowScrollStatus: false,
      canShowTextSelectionMenu: false,
      enableTextSelection: enableHighlight,
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

    // Issue 3 fix: pass ScrollMetrics to onScrollUpdate.
    // We use ScrollUpdateNotification so we get metrics on every scroll frame.
    // `return false` — do not absorb; let SfPdfViewer handle the scroll.
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        onScrollUpdate(notification.metrics);
        return false;
      },
      child: viewer,
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
  final ctrl = TextEditingController(text: '${currentPage + 1}');
  final formKey = GlobalKey<FormState>();
  try {
    return await showDialog<int>(
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
  } finally {
    ctrl.dispose();
  }
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
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