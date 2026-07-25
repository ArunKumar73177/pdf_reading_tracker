import 'package:flutter/material.dart';

import '../../theme/appearance_mode.dart';
import '../pdf_reader_actions.dart';

/// Icon button that opens the Bookmarks sheet with a live count badge.
class BookmarkButton extends StatelessWidget {
  const BookmarkButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.listenable,
        builder: (context, _) => IconButton(
          icon: Badge(
            isLabelVisible: actions.bookmarkCount > 0,
            label: Text('${actions.bookmarkCount}'),
            child: const Icon(Icons.bookmarks_outlined),
          ),
          color: color,
          tooltip: 'View bookmarks',
          onPressed: actions.showBookmarks,
        ),
      );
}

/// Icon button that opens the Notes sheet with a live count badge.
class NotesButton extends StatelessWidget {
  const NotesButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.listenable,
        builder: (context, _) => IconButton(
          icon: Badge(
            isLabelVisible: actions.noteCount > 0,
            label: Text('${actions.noteCount}'),
            child: const Icon(Icons.sticky_note_2_outlined),
          ),
          color: color,
          tooltip: 'View notes',
          onPressed: actions.showNotes,
        ),
      );
}

/// Icon button that opens the Annotations (highlights) sheet.
class HighlightsButton extends StatelessWidget {
  const HighlightsButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.listenable,
        builder: (context, _) => IconButton(
          icon: Badge(
            isLabelVisible: actions.highlightCount > 0,
            label: Text('${actions.highlightCount}'),
            child: const Icon(Icons.format_color_text_rounded),
          ),
          color: color,
          tooltip: 'View annotations',
          onPressed: actions.showHighlights,
        ),
      );
}

/// Icon button that toggles the plugin's own inline search bar.
class SearchButton extends StatelessWidget {
  const SearchButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.listenable,
        builder: (context, _) => IconButton(
          icon: Icon(actions.searchVisible
              ? Icons.search_off_rounded
              : Icons.search_rounded),
          color: color,
          tooltip: actions.searchVisible ? 'Close search' : 'Search text',
          onPressed: actions.toggleSearch,
        ),
      );
}

/// Icon button that opens the "Jump to page" dialog.
///
/// Kept as a standalone public widget for host apps that want to compose
/// their own layout. [PdfReaderToolbar] itself no longer places this
/// inline — see the class doc below for why.
class JumpToPageButton extends StatelessWidget {
  const JumpToPageButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.redo_rounded),
        color: color,
        tooltip: 'Jump to page',
        onPressed: actions.jumpToPage,
      );
}

/// Icon button that opens the Appearance picker sheet.
///
/// Kept as a standalone public widget for host apps that want to compose
/// their own layout. [PdfReaderToolbar] itself no longer places this
/// inline — see the class doc below for why.
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  static IconData iconFor(AppearanceMode mode) {
    switch (mode) {
      case AppearanceMode.light:
        return Icons.light_mode_rounded;
      case AppearanceMode.dark:
        return Icons.dark_mode_rounded;
      case AppearanceMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: actions.listenable,
        builder: (context, _) => IconButton(
          icon: Icon(iconFor(actions.appearanceMode)),
          color: color,
          tooltip: 'Appearance',
          onPressed: actions.showAppearanceSelector,
        ),
      );
}

/// Icon button that opens the Reading Settings sheet.
///
/// Kept as a standalone public widget for host apps that want to compose
/// their own layout. [PdfReaderToolbar] itself no longer places this
/// inline — see the class doc below for why.
class ReadingSettingsButton extends StatelessWidget {
  const ReadingSettingsButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.tune_rounded),
        color: color,
        tooltip: 'Reading settings',
        onPressed: actions.showReadingSettings,
      );
}

/// Overflow items shown in [PdfReaderToolbar]'s "more" menu. Mirrors the
/// private `_OverflowAction` enum in `pdf_reading_tracker_viewer.dart` —
/// duplicated (not shared) intentionally, since the two live in separate
/// libraries and this file must not import a plugin-private symbol.
enum _HostOverflowAction { jumpToPage, appearance, readingSettings }

/// Ready-made row combining bookmark / notes / highlights / search /
/// jump-to-page / appearance / reading-settings actions. Drop into a host
/// app's own `AppBar.actions` when using `showAppBar: false`.
///
/// ### Production-pass fix — parity with the plugin's own app bar
///
/// The plugin's built-in app bar (`_AppBarWithSearch` in
/// `pdf_reading_tracker_viewer.dart`) was decluttered to show only
/// Search · Notes · Highlights · Bookmarks inline, with Jump to page ·
/// Appearance · Reading settings moved into a single overflow menu — see
/// that file's audit note. This widget previously rendered all seven
/// actions inline, which meant a host app using the default
/// [PdfReaderToolbar] presented a visibly different (more crowded)
/// toolbar than the plugin's own chrome for the exact same feature set —
/// a `showAppBar:false` host and a `showAppBar:true` reader no longer
/// looked or behaved the same.
///
/// This now mirrors the plugin's layout exactly: Search, Notes,
/// Highlights, Bookmarks stay as individual always-visible icons; Jump to
/// page, Appearance, and Reading settings are grouped into one
/// `PopupMenuButton` (icon: `Icons.more_vert_rounded`), in the same order,
/// with the same icons/labels the plugin's overflow menu uses. No new
/// controllers or state were introduced — every action still forwards to
/// the exact same [PdfReaderActions] method it always called; only the
/// arrangement of existing buttons changed. The `show*` flags keep their
/// original meaning (whether an action is available at all); for
/// `showJumpToPage` / `showAppearance` / `showReadingSettings` they now
/// control whether that action's *entry inside the overflow menu*
/// appears, and the overflow button itself is omitted entirely if none of
/// the three are enabled.
///
/// ### Reader-UX redesign pass — icon spacing / touch targets
///
/// Icons are now separated with a small explicit gap (rather than relying
/// solely on `IconButton`'s own internal padding) and each gets a
/// rounded-rectangle Material 3 tap target via `IconButton.styleFrom`,
/// matching the plugin's own `_AppBarWithSearch` treatment — so a host
/// toolbar built from these widgets looks like the same "premium reader"
/// family as the plugin's built-in chrome, not a visually distinct row of
/// default Material icons. No callback, ordering, or `show*` flag
/// semantics changed.
///
/// Host apps that prefer a fully custom arrangement can still compose
/// [BookmarkButton], [NotesButton], [HighlightsButton], [SearchButton],
/// [JumpToPageButton], [AppearanceButton], and [ReadingSettingsButton]
/// directly instead of using this composite widget.
class PdfReaderToolbar extends StatelessWidget {
  const PdfReaderToolbar({
    super.key,
    required this.actions,
    this.color,
    this.showSearch = true,
    this.showNotes = true,
    this.showHighlights = true,
    this.showBookmarks = true,
    this.showJumpToPage = true,
    this.showAppearance = true,
    this.showReadingSettings = true,
  });

  final PdfReaderActions actions;
  final Color? color;
  final bool showSearch;
  final bool showNotes;
  final bool showHighlights;
  final bool showBookmarks;
  final bool showJumpToPage;
  final bool showAppearance;
  final bool showReadingSettings;

  static const double _kIconGap = 2.0;
  static const double _kTouchTargetRadius = 10.0;

  @override
  Widget build(BuildContext context) {
    final hasOverflowItems =
        showJumpToPage || showAppearance || showReadingSettings;

    final iconStyle = IconButton.styleFrom(
      foregroundColor: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kTouchTargetRadius),
      ),
      visualDensity: VisualDensity.compact,
    );

    return IconButtonTheme(
      data: IconButtonThemeData(style: iconStyle),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSearch) SearchButton(actions: actions, color: color),
          if (showSearch) const SizedBox(width: _kIconGap),
          if (showNotes) NotesButton(actions: actions, color: color),
          if (showNotes) const SizedBox(width: _kIconGap),
          if (showHighlights) HighlightsButton(actions: actions, color: color),
          if (showHighlights) const SizedBox(width: _kIconGap),
          if (showBookmarks) BookmarkButton(actions: actions, color: color),
          if (hasOverflowItems)
            PopupMenuButton<_HostOverflowAction>(
              icon: Icon(Icons.more_vert_rounded, color: color),
              tooltip: 'More',
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_kTouchTargetRadius),
              ),
              onSelected: (action) {
                switch (action) {
                  case _HostOverflowAction.jumpToPage:
                    actions.jumpToPage();
                  case _HostOverflowAction.appearance:
                    actions.showAppearanceSelector();
                  case _HostOverflowAction.readingSettings:
                    actions.showReadingSettings();
                }
              },
              itemBuilder: (context) => [
                if (showJumpToPage)
                  const PopupMenuItem(
                    value: _HostOverflowAction.jumpToPage,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.redo_rounded),
                      title: Text('Jump to page'),
                    ),
                  ),
                if (showAppearance)
                  PopupMenuItem(
                    value: _HostOverflowAction.appearance,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(AppearanceButton.iconFor(
                        actions.appearanceMode,
                      )),
                      title: const Text('Appearance'),
                    ),
                  ),
                if (showReadingSettings)
                  const PopupMenuItem(
                    value: _HostOverflowAction.readingSettings,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tune_rounded),
                      title: Text('Reading settings'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ImmersiveChromeVisibility
// ---------------------------------------------------------------------------

/// Wraps a host app's own chrome — its own `AppBar`, a custom toolbar row,
/// or any other widget — so it automatically hides and shows in lockstep
/// with the plugin's Immersive Mode.
///
/// ### Why this exists
///
/// [PdfReadingTrackerViewer] (via `showAppBar: true`) already hides its
/// *own* built-in app bar, bottom progress pill, and FAB together under
/// Immersive Mode, all driven by a single `ImmersiveVisibilityController`
/// — see that controller's class doc for the single-source-of-truth
/// design. A host app that renders its **own** app bar (`showAppBar:
/// false`, composing [PdfReaderToolbar] / [BookmarkButton] / etc. into
/// its own `Scaffold.appBar`) sits *outside* the plugin's widget tree, so
/// nothing hides it automatically — the host previously had to manually
/// listen to [PdfReaderActions.listenable] and read
/// [PdfReaderActions.immersiveChromeVisible] itself to replicate the
/// hide/show/animate behaviour.
///
/// This widget does exactly that wiring once, correctly, so host apps
/// don't have to re-implement it: wrap your own app bar in
/// [ImmersiveChromeVisibility] and it slides + fades out whenever the
/// plugin's chrome hides, and stays fully visible and interactive
/// whenever Immersive Mode is off — reading the *exact same*
/// `ImmersiveVisibilityController` state the plugin's built-in chrome
/// uses. No second controller, no independent timer: this widget owns no
/// state of its own beyond the `AnimatedSlide`/`AnimatedOpacity`
/// transition itself.
///
/// ### Usage
///
/// ```dart
/// final readerKey = GlobalKey<PdfReadingTrackerViewerState>();
///
/// Scaffold(
///   appBar: PreferredSize(
///     preferredSize: const Size.fromHeight(kToolbarHeight),
///     child: ImmersiveChromeVisibility(
///       actions: readerKey.currentState!.readerActions,
///       child: AppBar(
///         title: const Text('My PDF'),
///         actions: [
///           PdfReaderToolbar(actions: readerKey.currentState!.readerActions),
///         ],
///       ),
///     ),
///   ),
///   body: PdfReadingTrackerViewer(
///     key: readerKey,
///     showAppBar: false,
///     pdfId: 'my-pdf',
///     pdfTitle: 'My PDF',
///     filePath: '/path/to/file.pdf',
///   ),
/// )
/// ```
class ImmersiveChromeVisibility extends StatelessWidget {
  const ImmersiveChromeVisibility({
    super.key,
    required this.actions,
    required this.child,
    this.slideOffset = const Offset(0, -1),
  });

  /// The same [PdfReaderActions] instance obtained from
  /// `PdfReadingTrackerViewerState.readerActions`.
  final PdfReaderActions actions;

  /// The host app's own chrome — typically an `AppBar` or a `Row` of
  /// [PdfReaderToolbar] buttons.
  final Widget child;

  /// Direction [child] slides toward while hiding, as a fraction of its
  /// own size (same semantics as [AnimatedSlide.offset]). Defaults to
  /// sliding straight up and off-screen, matching the plugin's own app
  /// bar in `_buildImmersiveScaffold`.
  final Offset slideOffset;

  static const Duration _kDuration = Duration(milliseconds: 220);
  static const Curve _kCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: actions.listenable,
      builder: (context, _) {
        // When Immersive Mode is off, `immersiveChromeVisible` is always
        // `true` (see `ImmersiveVisibilityController`), so this widget is
        // a permanent no-op passthrough in classic mode — exactly the
        // "everything stays visible" requirement, with zero extra state.
        final visible = actions.immersiveChromeVisible;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            duration: _kDuration,
            curve: _kCurve,
            offset: visible ? Offset.zero : slideOffset,
            child: AnimatedOpacity(
              duration: _kDuration,
              curve: _kCurve,
              opacity: visible ? 1.0 : 0.0,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
