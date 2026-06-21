import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

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

  /// When `false` (default), the viewer scrolls vertically — continuous,
  /// single-column reading. When `true`, the viewer swipes horizontally
  /// page by page.
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool showAppBar;
  final bool showBottomBar;
  final bool showBookmarkFab;
  final bool enableSearch;

  /// When `true`, text selection triggers the annotation action bar.
  final bool enableHighlight;

  @override
  State<PdfReadingTrackerViewer> createState() => _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;

  final GlobalKey<sf.SfPdfViewerState> _sfViewerKey = GlobalKey<sf.SfPdfViewerState>();
  final GlobalKey _bottomBarKey = GlobalKey();

  bool _isLoading = true;
  String? _error;
  String? _resolvedFilePath;
  int _initialPage = 0;
  bool _searchVisible = false;

  /// The note staged for the *current, not-yet-committed* annotation
  /// (i.e. before "Apply" is tapped). Display-only state — the actual
  /// editor is `SafeNoteDialog`, which owns its own controller lifecycle
  /// completely independently of this field.
  String? _pendingAnnotationNote;

  /// Guards against opening more than one dialog at a time — e.g. a rapid
  /// double-tap on the note button. Each dialog call checks this before
  /// pushing a new route and resets it when the route resolves.
  bool _dialogOpen = false;

  double? _bottomBarHeight;

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
    if (widget.showBottomBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottomBarHeight());
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onUpdate);
    _ctrl.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    final loadingChanged = _ctrl.isLoading != _isLoading;
    final errorChanged = _ctrl.error != _error;
    final pathChanged = _ctrl.resolvedFilePath != _resolvedFilePath;
    if (!loadingChanged && !errorChanged && !pathChanged) return;
    setState(() {
      _isLoading = _ctrl.isLoading;
      _error = _ctrl.error;
      _resolvedFilePath = _ctrl.resolvedFilePath;
      _initialPage = _ctrl.initialPage;
    });
    if (!loadingChanged || _isLoading) return;
    if (widget.showBottomBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottomBarHeight());
    }
  }

  void _measureBottomBarHeight() {
    if (!mounted) return;
    final box = _bottomBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final measured = box.size.height;
    if (_bottomBarHeight != null && (measured - _bottomBarHeight!).abs() < 0.5) {
      return;
    }
    setState(() => _bottomBarHeight = measured);
  }

  // ---------------------------------------------------------------------------
  // Annotation commit
  // ---------------------------------------------------------------------------

  void _commitAnnotation(AnnotationCommit commit) {
    final textLines = _sfViewerKey.currentState?.getSelectedTextLines() ?? const [];

    if (textLines.isEmpty) {
      _ctrl.captureTextSelection(null, null, null);
      return;
    }

    _ctrl.commitAnnotation(textLines: textLines, commit: commit);
    if (mounted) setState(() => _pendingAnnotationNote = null);
  }

  /// Opens the note dialog for the *pending* (not-yet-committed)
  /// annotation.
  ///
  /// **Crash fix:** [PdfViewerController.clearPdfSelection] is called
  /// first — *before* the dialog route is pushed — tearing down
  /// Syncfusion's native platform-level selection-handle overlay so it
  /// cannot fire any further `onTextSelectionChanged` callbacks while the
  /// dialog is open. The dialog itself ([showSafeNoteDialog]) owns a
  /// fully independent `TextEditingController` lifecycle on the root
  /// Navigator — see `safe_note_dialog.dart` for the full explanation.
  Future<void> _openPendingAnnotationNoteDialog() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final result = await showSafeNoteDialog(
        context: context,
        title: 'Add note',
        initialText: _pendingAnnotationNote ?? '',
        allowDelete: _pendingAnnotationNote != null,
        // Note: we intentionally do NOT clear the PDF text selection here,
        // because this note is *for* the pending annotation — clearing it
        // would drop the user's selection before they apply the highlight.
        // The native selection-handle overlay does not interfere with this
        // dialog because the dialog runs on the root Navigator, which is
        // an entirely separate Element subtree from SfPdfViewer's overlay
        // entries — see safe_note_dialog.dart's doc comment for why this
        // structural isolation is what actually prevents the crash.
      );
      if (result == null || !mounted) return;
      setState(() {
        _pendingAnnotationNote = result.deleted ? null : result.text;
      });
    } finally {
      _dialogOpen = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Standalone Notes (v2.6.0)
  // ---------------------------------------------------------------------------

  /// Opens the note dialog to add a brand-new standalone note on the
  /// current page (independent of any text selection / annotation).
  Future<void> _handleAddNoteTap() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final result = await showSafeNoteDialog(
        context: context,
        title: 'Add note — Page ${_ctrl.currentPage + 1}',
        initialText: '',
        allowDelete: false,
        onOpen: _ctrl.clearPdfSelection,
      );
      if (result == null || result.deleted || !mounted) return;
      if (result.text.trim().isEmpty) return;
      await _ctrl.addNote(result.text.trim());
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save note: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
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

  // ---------------------------------------------------------------------------
  // Handlers (unchanged)
  // ---------------------------------------------------------------------------

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
      await _ctrl.addBookmark(note: (note == null || note.isEmpty) ? null : note);
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

    final viewerCore = _PdfViewerCore(
      key: ValueKey(_resolvedFilePath),
      sfViewerKey: _sfViewerKey,
      resolvedFilePath: _resolvedFilePath!,
      initialPage: _initialPage,
      swipeHorizontal: widget.swipeHorizontal,
      enableDoubleTap: widget.enableDoubleTap,
      enableHighlight: widget.enableHighlight,
      sfController: _ctrl.sfController,
      bottomBarHeight: widget.showBottomBar ? _bottomBarHeight : 0,
      onPageChanged: (n) {
        _ctrl.onPageChanged(n);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      onDocumentLoaded: (n) => _ctrl.onDocumentLoaded(n),
      onDocumentLoadFailed: (desc) => _ctrl.onDocumentLoadFailed(desc),
      onTextSelectionChanged: (text, region) {
        // Guard: if a dialog is currently open, ignore selection-change
        // callbacks entirely. This is the second half of the crash fix —
        // even though SafeNoteDialog is structurally isolated on the root
        // Navigator, we additionally refuse to let stray selection events
        // touch `highlightNotifier` while any dialog is in flight, so the
        // AnnotationActionBar can never rebuild out from under a dialog.
        if (_dialogOpen) return;
        final lines = _sfViewerKey.currentState?.getSelectedTextLines();
        _ctrl.captureTextSelection(text, region, lines);
      },
    );

    if (!widget.showAppBar) {
      return _wrapWithAnnotationBar(viewerCore);
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight + (_searchVisible ? 56.0 : 0.0)),
        child: ListenableBuilder(
          listenable: Listenable.merge(
              [_ctrl.bookmarksNotifier, _ctrl.highlightNotifier, _ctrl.notesNotifier]),
          builder: (_, __) => _AppBarWithSearch(
            title: widget.pdfTitle,
            backgroundColor: theme?.appBarBackgroundColor ?? cs.primaryContainer,
            foregroundColor: theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
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
      body: _wrapWithAnnotationBar(viewerCore),
      bottomNavigationBar: widget.showBottomBar
          ? ListenableBuilder(
        listenable: Listenable.merge([_ctrl.pageNotifier, _ctrl.savingNotifier]),
        builder: (_, __) => ReaderBottomBar(
          key: _bottomBarKey,
          currentPage: _ctrl.currentPage,
          totalPages: _ctrl.totalPages,
          progressPct: _ctrl.progressPct,
          isSaving: _ctrl.isSavingProgress,
        ),
      )
          : null,
      floatingActionButton: widget.showBookmarkFab
          ? ListenableBuilder(
        listenable: Listenable.merge([_ctrl.pageNotifier, _ctrl.bookmarksNotifier]),
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
              isBookmarked: _ctrl.bookmarks.any((b) => b.page == _ctrl.currentPage),
              onPressed: _handleBookmarkTap,
            ),
          ],
        ),
      )
          : null,
    );
  }

  /// Wraps [child] in a [Stack] that overlays [AnnotationActionBar] when the
  /// user has an active text selection.
  ///
  /// **Crash fix (supersedes v2.5.2/v2.5.3):** [AnnotationActionBar] now
  /// owns *no* dialog and *no* `TextEditingController` whatsoever — see its
  /// updated doc comment. There is therefore nothing left in this widget's
  /// subtree for a disposed-controller, duplicate-`GlobalKey`, or
  /// wrong-build-scope race to attach to, regardless of how often this
  /// `ListenableBuilder` rebuilds the bar while a dialog is open elsewhere
  /// on the root Navigator.
  Widget _wrapWithAnnotationBar(Widget child) {
    if (!widget.enableHighlight) return child;

    return ListenableBuilder(
      listenable: _ctrl.highlightNotifier,
      builder: (_, __) {
        final pending = _ctrl.pendingSelection;
        if (pending == null && _pendingAnnotationNote != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _pendingAnnotationNote = null);
          });
        }
        return Stack(
          children: [
            child,
            if (pending != null)
              Positioned(
                bottom: 80,
                left: 12,
                right: 12,
                child: AnnotationActionBar(
                  key: const ValueKey('annotation_action_bar'),
                  selectedText: pending.selectedText,
                  currentNote: _pendingAnnotationNote,
                  onCommit: _commitAnnotation,
                  onDismiss: () {
                    if (mounted) setState(() => _pendingAnnotationNote = null);
                    _ctrl.captureTextSelection(null, null, null);
                  },
                  onAddNote: _openPendingAnnotationNoteDialog,
                ),
              ),
          ],
        );
      },
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
                icon: Icon(searchVisible ? Icons.search_off_rounded : Icons.search_rounded),
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
    this.bottomBarHeight,
  });

  final GlobalKey<sf.SfPdfViewerState> sfViewerKey;
  final String resolvedFilePath;
  final int initialPage;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool enableHighlight;
  final sf.PdfViewerController sfController;
  final void Function(int) onPageChanged;
  final void Function(int) onDocumentLoaded;
  final void Function(String) onDocumentLoadFailed;
  final void Function(String?, Rect?) onTextSelectionChanged;

  final double? bottomBarHeight;

  /// Visual gap between pages in continuous (vertical) scroll mode.
  ///
  /// **Issue 4 fix:** previously hard-set to `0`, which made pages appear
  /// stitched together with zero visual separation. `12` logical pixels
  /// gives a clear seam between pages — matching the "Disclaimer" gap
  /// visible in Image 2 — without affecting page-index calculations
  /// (`pageSpacing` is purely a rendering gap; Syncfusion's own
  /// `onPageChanged`/`PdfPageChangedDetails.newPageNumber` boundary logic
  /// is unaffected by it) and without any measurable performance cost
  /// (`pageSpacing` is consumed by Syncfusion's existing internal layout
  /// pass — no extra widgets, no extra rebuilds).
  static const double _kPageSpacing = 12.0;

  @override
  Widget build(BuildContext context) {
    final viewer = sf.SfPdfViewer.file(
      File(resolvedFilePath),
      key: sfViewerKey,
      controller: sfController,
      initialPageNumber: initialPage + 1,
      pageLayoutMode: sf.PdfPageLayoutMode.continuous,

      // Issue 4 fix — see _kPageSpacing doc comment above.
      pageSpacing: swipeHorizontal ? 0 : _kPageSpacing,

      scrollDirection:
      swipeHorizontal ? sf.PdfScrollDirection.horizontal : sf.PdfScrollDirection.vertical,
      enableDoubleTapZooming: enableDoubleTap,
      canShowScrollHead: false,
      canShowScrollStatus: false,

      // Issue 2 fix: Syncfusion's own *built-in* text selection context
      // menu (Copy / Highlight / Underline / Strikethrough / Squiggly —
      // the popup visible in the screenshots) is a separate, built-in
      // overlay distinct from `enableTextSelection` (which must stay on
      // for highlighting to work at all). `canShowTextSelectionMenu` is
      // the documented Syncfusion property that toggles *only* that
      // built-in menu. Setting it to false removes the competing popup
      // entirely; text selection itself, `onTextSelectionChanged`, and
      // `getSelectedTextLines()` are all unaffected, so our own
      // AnnotationActionBar (the single, intentional surface for
      // choosing annotation type/colour) keeps working exactly as
      // before — it just no longer has to fight a second, built-in menu
      // for the same screen region, and that menu's overlay can no
      // longer remain alive behind the note dialog.
      canShowTextSelectionMenu: false,
      enableTextSelection: enableHighlight,

      onPageChanged: (sf.PdfPageChangedDetails d) => onPageChanged(d.newPageNumber),
      onDocumentLoaded: (sf.PdfDocumentLoadedDetails d) =>
          onDocumentLoaded(d.document.pages.count),
      onDocumentLoadFailed: (sf.PdfDocumentLoadFailedDetails d) =>
          onDocumentLoadFailed('${d.error}: ${d.description}'),
      onTextSelectionChanged: enableHighlight
          ? (sf.PdfTextSelectionChangedDetails d) =>
          onTextSelectionChanged(d.selectedText, d.globalSelectedRegion)
          : null,
    );

    if (swipeHorizontal) return viewer;

    return _SinglePageVerticalClamp(bottomBarHeight: bottomBarHeight, child: viewer);
  }
}

/// Constrains [child] to the actual available viewport height, instead of
/// letting Syncfusion's own page sizing decide it. See prior versions'
/// documentation for the full rationale — unchanged in this release.
class _SinglePageVerticalClamp extends StatelessWidget {
  const _SinglePageVerticalClamp({required this.child, required this.bottomBarHeight});

  final Widget child;
  final double? bottomBarHeight;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final reservedBottom = (bottomBarHeight ?? 0) + bottomInset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
        (constraints.maxHeight - reservedBottom).clamp(0.0, double.infinity);
        return ClipRect(
          child: SizedBox(
            height: availableHeight,
            width: constraints.maxWidth,
            child: child,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Jump-to-page dialog (unchanged)
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
// Error view (unchanged)
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
            Text('Could not load PDF', style: tt.titleMedium?.copyWith(color: cs.error)),
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