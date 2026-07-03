import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as sf;

import '../immersive/dnd/dnd_service.dart';
import '../immersive/immersive_visibility_controller.dart';
import '../immersive/reading_settings.dart';
import '../immersive/reading_settings_controller.dart';
import '../immersive/widgets/immersive_gesture_layer.dart';
import '../immersive/widgets/reading_settings_sheet.dart';
import '../models/note.dart';
import '../services/bookmark_service.dart';
import '../theme/appearance_controller.dart';
import '../theme/appearance_mode.dart';
import '../theme/design_tokens.dart';
import 'pdf_search_controller.dart';
import 'pdf_viewer_controller.dart';
import 'widgets/annotation_action_bar.dart';
import 'widgets/appearance_selector_sheet.dart';
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

/// ### Stability-pass architecture note (read before modifying this file)
///
/// [build] and [_buildBody] deliberately **never** call `Theme.of(context)`
/// in the loaded-reader code path, and nothing between the top-level
/// `AnimatedTheme` and [_PdfViewerCore] establishes a `Theme` inherited
/// dependency. This is load-bearing, not stylistic:
///
/// `AnimatedTheme` updates its internal `Theme` InheritedWidget on every
/// animation frame while interpolating between appearance modes (~12
/// frames over its 200ms transition). Any widget between it and
/// `SfPdfViewer` that calls `Theme.of(context)` becomes a dependent of
/// that InheritedWidget and gets forcibly rebuilt on *every one of those
/// frames*, regardless of the `AnimatedBuilder`/`ListenableBuilder`
/// `child` optimization — inherited-widget notification bypasses that
/// optimization entirely. A previous version of this file called
/// `Theme.of(context)` at the top of the method now split into
/// [_buildBody]/[_buildLoadedContent], which reconstructed the entire
/// scaffold — including [_PdfViewerCore], i.e. `SfPdfViewer` itself — on
/// every appearance-transition frame. That violates the "SfPdfViewer must
/// never rebuild" requirement and was the root cause of the reader
/// toolbar intermittently disappearing after repeated appearance changes.
///
/// All colour resolution for the loaded reader now happens **only** in
/// leaf widgets ([_AppBarWithSearch]) that call `Theme.of(context)` in
/// their own, independently-triggered `build()` — never passed down as a
/// value captured higher in the tree.
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
    this.showAppearanceToggle = true,
    this.initialAppearanceMode = AppearanceMode.system,
    this.onAppearanceModeChanged,
    this.initialReadingSettings,
    this.showReadingSettingsToggle = true,
    this.onReadingSettingsChanged,
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
  final bool showAppearanceToggle;
  final AppearanceMode initialAppearanceMode;
  final void Function(AppearanceMode mode)? onAppearanceModeChanged;
  final ReadingSettings? initialReadingSettings;
  final bool showReadingSettingsToggle;
  final void Function(ReadingSettings settings)? onReadingSettingsChanged;

  @override
  State<PdfReadingTrackerViewer> createState() =>
      _PdfReadingTrackerViewerState();
}

class _PdfReadingTrackerViewerState extends State<PdfReadingTrackerViewer> {
  late final PdfViewerController _ctrl;
  late final AppearanceController _appearance;
  late final ReadingSettingsController _readingSettings;
  late final ImmersiveVisibilityController _immersiveVisibility;
  late final DndService _dndService;

  final GlobalKey<sf.SfPdfViewerState> _sfViewerKey =
  GlobalKey<sf.SfPdfViewerState>();

  bool _isLoading = true;
  String? _error;
  String? _resolvedFilePath;
  int _initialPage = 0;
  bool _searchVisible = false;
  bool _dialogOpen = false;

  bool _scrollDetectionActive = false;

  @override
  void initState() {
    super.initState();
    _ctrl = PdfViewerController(
      pdfId: widget.pdfId,
      pdfTitle: widget.pdfTitle,
      assetPath: widget.assetPath,
      filePath: widget.filePath,
      onDeviceFilePath: widget.filePath,
      swipeHorizontal: widget.swipeHorizontal,
      pageSpacing: _PdfViewerCore._kPageSpacing,
    );
    _ctrl.addListener(_onControllerUpdate);
    _ctrl.init();

    _appearance =
    AppearanceController(initialMode: widget.initialAppearanceMode)
      ..init();

    _readingSettings =
    ReadingSettingsController(initial: widget.initialReadingSettings)
      ..init();
    _readingSettings.addListener(_onReadingSettingsChanged);

    _immersiveVisibility =
    ImmersiveVisibilityController(settings: _readingSettings)..init();

    _dndService = DndServiceProvider.create();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerUpdate);
    _ctrl.dispose();
    _appearance.dispose();
    _readingSettings.removeListener(_onReadingSettingsChanged);
    _immersiveVisibility.dispose();
    _readingSettings.dispose();
    _dndService.dispose();
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

  void _onReadingSettingsChanged() {
    widget.onReadingSettingsChanged?.call(_readingSettings.value);
  }

  Future<void> _showAppearanceSelector() async {
    await showAppearanceSelectorSheet(
      context: context,
      current: _appearance.mode,
      onSelected: (mode) {
        _appearance.setMode(mode);
        widget.onAppearanceModeChanged?.call(mode);
      },
    );
  }

  Future<void> _showReadingSettings() async {
    await showReadingSettingsSheet(
      context: context,
      controller: _readingSettings,
      dndService: _dndService,
    );
  }

  void _commitAnnotation(AnnotationCommit commit) {
    final textLines =
        _sfViewerKey.currentState?.getSelectedTextLines() ?? const [];
    if (textLines.isEmpty) {
      _ctrl.captureTextSelection(null, null, null);
      return;
    }
    _ctrl.commitAnnotation(textLines: textLines, commit: commit);
  }

  Future<void> _handleAddNoteTap() async {
    if (_dialogOpen) return;
    _dialogOpen = true;

    final snapshot = _ctrl.snapshotSelection;
    final capturedText = snapshot?.selectedText ?? '';
    final capturedPage = snapshot?.page;
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
        page: capturedPage,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save note: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
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
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      final page = await showDialog<int>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _JumpToPageDialog(
          currentPage: _ctrl.currentPage,
          totalPages: _ctrl.totalPages,
        ),
      );
      if (page != null && mounted) await _ctrl.goToPage(page);
    } finally {
      _dialogOpen = false;
    }
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
    // Only `_appearance` drives this outer layer, and its `builder`
    // callback below does NOT call `Theme.of(context)` — it only reads
    // `_appearance.themeData` (a plain Dart getter, not an inherited
    // lookup) to feed `AnimatedTheme.data`. This means `child` (the whole
    // reader) is genuinely never touched by appearance transitions; the
    // ambient Theme still propagates to every descendant that reads it in
    // its own build via the normal InheritedWidget mechanism.
    return ListenableBuilder(
      listenable: _appearance,
      builder: (context, child) => AnimatedTheme(
        data: _appearance.themeData,
        duration: AppDurations.medium,
        curve: AppDurations.curve,
        child: child!,
      ),
      child: Builder(builder: _buildBody),
    );
  }

  /// Handles the loading / error / loaded top-level branching. Only
  /// re-runs on a genuine `State.build()` (i.e. `setState` from
  /// `_onControllerUpdate` or `_toggleSearch`) — never on an appearance or
  /// reading-settings notification alone (see class doc).
  ///
  /// `Theme.of(context)` is used here ONLY for the loading/error branches,
  /// which never mount `SfPdfViewer` — safe, since there is nothing below
  /// them for an inherited-widget rebuild storm to reach.
  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      final cs = Theme.of(context).colorScheme;
      return widget.showAppBar
          ? Scaffold(
        appBar: AppBar(
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
          backgroundColor:
          widget.theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor:
          widget.theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: const Center(child: CircularProgressIndicator()),
      )
          : const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      final cs = Theme.of(context).colorScheme;
      final errorBody = _ErrorView(message: _error!, onRetry: _ctrl.init);
      return widget.showAppBar
          ? Scaffold(
        appBar: AppBar(
          title: Text(widget.pdfTitle, overflow: TextOverflow.ellipsis),
          backgroundColor:
          widget.theme?.appBarBackgroundColor ?? cs.primaryContainer,
          foregroundColor:
          widget.theme?.appBarForegroundColor ?? cs.onPrimaryContainer,
        ),
        body: errorBody,
      )
          : errorBody;
    }

    return _buildLoadedContent();
  }

  /// The real reader UI. **No `Theme.of(context)` call anywhere in this
  /// method or anything it calls above `_PdfViewerCore`** — see class doc.
  /// `overlayStack` (which contains `_PdfViewerCore` / `SfPdfViewer`) is
  /// built exactly once here and handed down as a `child` to the
  /// `_readingSettings` `ListenableBuilder` below, so neither an
  /// appearance change nor a reading-settings change ever reconstructs it.
  Widget _buildLoadedContent() {
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
        if (!_scrollDetectionActive) {
          _ctrl.onPageChanged(n);
          widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
        }
      },
      onScrollUpdate: (metrics) {
        if (!_scrollDetectionActive) {
          _scrollDetectionActive = true;
        }
        _ctrl.onScrollUpdate(metrics);
        widget.onPageChanged?.call(_ctrl.currentPage, _ctrl.totalPages);
      },
      onDocumentLoaded: (pageCount, document) {
        _scrollDetectionActive = false;
        _ctrl.onDocumentLoaded(pageCount, document);
      },
      onDocumentLoadFailed: _ctrl.onDocumentLoadFailed,
      onTextSelectionChanged: (text, region) {
        if (_dialogOpen) return;
        final lines = _sfViewerKey.currentState?.getSelectedTextLines();
        _ctrl.captureTextSelection(text, region, lines);
      },
      onViewportSizeChanged: _ctrl.onViewportSizeChanged,
    );

    final overlayStack = _buildOverlayStack(viewerCore);

    if (!widget.showAppBar) return overlayStack;

    final fab = widget.showBookmarkFab ? _buildAnimatedFab() : null;

    // Isolated ListenableBuilder: rebuilds ONLY the thin Scaffold-shape
    // decision on a reading-settings change. `overlayStack` (and
    // therefore SfPdfViewer) is passed through as `child` — this builder
    // callback never calls Theme.of(context), so it does not become an
    // AnimatedTheme dependent and does not get swept into any
    // appearance-transition rebuild storm either.
    return ListenableBuilder(
      listenable: _readingSettings,
      builder: (context, child) => _readingSettings.value.immersiveModeEnabled
          ? _buildImmersiveScaffold(body: child!, fab: fab)
          : _buildClassicScaffold(body: child!, fab: fab),
      child: overlayStack,
    );
  }

  // -------------------------------------------------------------------------
  // Classic scaffold (Immersive Mode off) — identical to the pre-Phase-3
  // reader. No Theme.of(context) here — _AppBarWithSearch resolves its
  // own colors.
  // -------------------------------------------------------------------------

  Widget _buildClassicScaffold({required Widget body, required Widget? fab}) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
            kToolbarHeight + (_searchVisible ? 56.0 : 0.0)),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _ctrl.bookmarksNotifier,
            _ctrl.highlightNotifier,
            _ctrl.notesNotifier,
            _appearance,
          ]),
          builder: (_, __) => _buildAppBarContent(),
        ),
      ),
      body: body,
      floatingActionButton: fab,
    );
  }

  // -------------------------------------------------------------------------
  // Immersive scaffold (Immersive Mode on) — full-bleed PDF surface with a
  // floating, animated app bar and FAB. No Theme.of(context) here either —
  // `Material` below reads the ambient theme implicitly via its own
  // `color` param, which itself is resolved inside _buildAppBarContent.
  // -------------------------------------------------------------------------

  Widget _buildImmersiveScaffold({
    required Widget body,
    required Widget? fab,
  }) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _immersiveVisibility,
                _ctrl.bookmarksNotifier,
                _ctrl.highlightNotifier,
                _ctrl.notesNotifier,
                _appearance,
              ]),
              builder: (context, _) {
                final visible = _immersiveVisibility.chromeVisible;
                return IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedSlide(
                    duration: AppDurations.medium,
                    curve: AppDurations.curve,
                    offset: visible ? Offset.zero : const Offset(0, -1),
                    child: AnimatedOpacity(
                      duration: AppDurations.medium,
                      curve: AppDurations.curve,
                      opacity: visible ? 1.0 : 0.0,
                      child: RepaintBoundary(
                        // `Material.color` reads `null` here and lets
                        // _AppBarWithSearch's own AppBar paint the
                        // background — avoids resolving colorScheme at
                        // this level too.
                        child: Material(
                          color: Colors.transparent,
                          elevation: AppElevation.medium,
                          child: SafeArea(
                            bottom: false,
                            child: _buildAppBarContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: fab,
    );
  }

  /// Builds the app bar widget itself. Colour resolution happens entirely
  /// inside [_AppBarWithSearch]'s own `build()` via `Theme.of(context)` —
  /// this method passes only the optional host override
  /// ([PdfViewerTheme]) through, never a pre-resolved [Color].
  Widget _buildAppBarContent() {
    return _AppBarWithSearch(
      title: widget.pdfTitle,
      viewerTheme: widget.theme,
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
      showAppearanceToggle: widget.showAppearanceToggle,
      appearanceMode: _appearance.mode,
      onOpenAppearanceSelector: _showAppearanceSelector,
      showReadingSettingsToggle: widget.showReadingSettingsToggle,
      onOpenReadingSettings: _showReadingSettings,
    );
  }

  Widget _buildAnimatedFab() {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [_ctrl.pageNotifier, _ctrl.bookmarksNotifier, _immersiveVisibility]),
      builder: (_, __) {
        final visible = _immersiveVisibility.chromeVisible;
        return RepaintBoundary(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              duration: AppDurations.medium,
              curve: AppDurations.curve,
              offset: visible ? Offset.zero : const Offset(0, 0.3),
              child: AnimatedOpacity(
                duration: AppDurations.medium,
                curve: AppDurations.curve,
                opacity: visible ? 1.0 : 0.0,
                child: Column(
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
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Overlay stack
  // -------------------------------------------------------------------------

  Widget _buildOverlayStack(Widget viewerCore) {
    return Stack(
      children: [
        ListenableBuilder(
          listenable: _readingSettings,
          builder: (context, child) => ImmersiveGestureLayer(
            enabled: _readingSettings.value.immersiveModeEnabled,
            onTap: _immersiveVisibility.toggle,
            child: child!,
          ),
          child: viewerCore,
        ),

        ListenableBuilder(
          listenable: _ctrl.highlightNotifier,
          builder: (context, __) {
            final pending = _ctrl.pendingSelection;
            return Positioned(
              bottom: 72,
              left: 12,
              right: 12,
              child: (widget.enableHighlight && pending != null)
                  ? AnnotationActionBar(
                key: const ValueKey('annotation_action_bar'),
                selectedText: pending.selectedText,
                onCommit: _commitAnnotation,
                onDismiss: () {
                  _ctrl.captureTextSelection(null, null, null);
                  _ctrl.clearSnapshot();
                },
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
              displayPercent: _ctrl.displayPercent,
              isSaving: _ctrl.isSavingProgress,
              noteCountOnCurrentPage: _ctrl.noteCountOnCurrentPage,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _JumpToPageDialog (unchanged)
// ---------------------------------------------------------------------------

class _JumpToPageDialog extends StatefulWidget {
  const _JumpToPageDialog({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  State<_JumpToPageDialog> createState() => _JumpToPageDialogState();
}

class _JumpToPageDialogState extends State<_JumpToPageDialog> {
  late final TextEditingController _textCtrl;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: '${widget.currentPage + 1}');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!mounted) return;
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(int.parse(_textCtrl.text.trim()) - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = widget.totalPages;

    if (totalPages <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return AlertDialog(
      title: const Text('Jump to page'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _textCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textInputAction: TextInputAction.go,
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
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AppBar with collapsible search + appearance toggle + reading settings
//
// ### Stability-pass fix — no hardcoded / passed-in colors
//
// Previously received pre-resolved `backgroundColor`/`foregroundColor`
// values computed once, far up the tree, from a `Theme.of(context)` call
// that could go stale (this was bug #2, and contributed to bug #1 — see
// the class doc on `_PdfReadingTrackerViewerState`). This widget now
// receives only the optional host-supplied [PdfViewerTheme] override and
// resolves the *actual* colors itself, live, from `Theme.of(context)` in
// its own `build()` — the only correct place to do so, since this widget
// is rebuilt independently by its own `ListenableBuilder` and reading
// `Theme.of(context)` here cannot cascade into rebuilding `SfPdfViewer`
// (this widget has no descendant that mounts it).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// AppBar with collapsible search + overflow menu
//
// ### Priority #3 / #6 audit fix — decluttered toolbar
//
// Previously rendered 7 permanent icons (reading settings, appearance,
// search, jump-to-page, notes, highlights, bookmarks). That's too many for
// a "minimal, reader-focused" toolbar per the spec.
//
// Kept visible (highest-frequency, core-to-the-package actions):
//   Search · Notes · Highlights · Bookmarks  (the last three carry the
//   badge counts users check constantly while reading)
//
// Moved into a single overflow menu (settings-like, opened rarely):
//   Jump to page · Appearance · Reading settings
//
// No functionality removed — every action is still one tap (search/notes/
// highlights/bookmarks) or two taps (overflow items) away, same callbacks,
// same public API surface.
//
// ### Stability-pass note (unchanged from before)
//
// This widget receives only the optional host-supplied [PdfViewerTheme]
// override and resolves the actual colors itself, live, from
// `Theme.of(context)` in its own `build()` — the only correct place to do
// so, since this widget is rebuilt independently by its own
// `ListenableBuilder` and reading `Theme.of(context)` here cannot cascade
// into rebuilding `SfPdfViewer`.
// ---------------------------------------------------------------------------

enum _OverflowAction { jumpToPage, appearance, readingSettings }

class _AppBarWithSearch extends StatelessWidget {
  const _AppBarWithSearch({
    required this.title,
    required this.viewerTheme,
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
    required this.showAppearanceToggle,
    required this.appearanceMode,
    required this.onOpenAppearanceSelector,
    required this.showReadingSettingsToggle,
    required this.onOpenReadingSettings,
  });

  final String title;

  /// Host-app color override, if any. `null` fields fall back to the
  /// live `ColorScheme` resolved in [build].
  final PdfViewerTheme? viewerTheme;

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
  final bool showAppearanceToggle;
  final AppearanceMode appearanceMode;
  final VoidCallback onOpenAppearanceSelector;
  final bool showReadingSettingsToggle;
  final VoidCallback onOpenReadingSettings;

  IconData get _appearanceIcon {
    switch (appearanceMode) {
      case AppearanceMode.light:
        return Icons.light_mode_rounded;
      case AppearanceMode.dark:
        return Icons.dark_mode_rounded;
      case AppearanceMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live read, resolved fresh every time THIS widget is rebuilt by its
    // own ListenableBuilder — never captured/frozen from an ancestor.
    final cs = Theme.of(context).colorScheme;
    final backgroundColor =
        viewerTheme?.appBarBackgroundColor ?? cs.primaryContainer;
    final foregroundColor =
        viewerTheme?.appBarForegroundColor ?? cs.onPrimaryContainer;

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
            PopupMenuButton<_OverflowAction>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'More',
              onSelected: (action) {
                switch (action) {
                  case _OverflowAction.jumpToPage:
                    onJumpToPage();
                  case _OverflowAction.appearance:
                    onOpenAppearanceSelector();
                  case _OverflowAction.readingSettings:
                    onOpenReadingSettings();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _OverflowAction.jumpToPage,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.redo_rounded),
                    title: Text('Jump to page'),
                  ),
                ),
                if (showAppearanceToggle)
                  PopupMenuItem(
                    value: _OverflowAction.appearance,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_appearanceIcon),
                      title: const Text('Appearance'),
                    ),
                  ),
                if (showReadingSettingsToggle)
                  const PopupMenuItem(
                    value: _OverflowAction.readingSettings,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune_rounded),
                      title: Text('Reading settings'),
                    ),
                  ),
              ],
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
// _PdfViewerCore (unchanged — never touches Theme.of(context))
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
    required this.onViewportSizeChanged,
  });

  final GlobalKey<sf.SfPdfViewerState> sfViewerKey;
  final String resolvedFilePath;
  final int initialPage;
  final bool swipeHorizontal;
  final bool enableDoubleTap;
  final bool enableHighlight;
  final sf.PdfViewerController sfController;
  final void Function(int) onPageChanged;
  final void Function(ScrollMetrics metrics) onScrollUpdate;
  final void Function(int pageCount, sf.PdfDocument document) onDocumentLoaded;
  final void Function(String) onDocumentLoadFailed;
  final void Function(String?, Rect?) onTextSelectionChanged;
  final void Function(Size size) onViewportSizeChanged;

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
          onDocumentLoaded(d.document.pages.count, d.document),
      onDocumentLoadFailed: (sf.PdfDocumentLoadFailedDetails d) =>
          onDocumentLoadFailed('${d.error}: ${d.description}'),
      onTextSelectionChanged: enableHighlight
          ? (sf.PdfTextSelectionChangedDetails d) =>
          onTextSelectionChanged(d.selectedText, d.globalSelectedRegion)
          : null,
    );

    final scrollAware = NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        onScrollUpdate(notification.metrics);
        return false;
      },
      child: viewer,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onViewportSizeChanged(size);
        });
        return scrollAware;
      },
    );
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