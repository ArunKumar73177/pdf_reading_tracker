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
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, required this.actions, this.color});
  final PdfReaderActions actions;
  final Color? color;

  static IconData _iconFor(AppearanceMode mode) {
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
          icon: Icon(_iconFor(actions.appearanceMode)),
          color: color,
          tooltip: 'Appearance',
          onPressed: actions.showAppearanceSelector,
        ),
      );
}

/// Icon button that opens the Reading Settings sheet.
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

/// Ready-made row combining all of the above. Drop into a host app's own
/// `AppBar.actions` when using `showAppBar: false`. Toggle individual
/// buttons off via the `show*` flags, or compose them yourself instead.
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

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSearch) SearchButton(actions: actions, color: color),
          if (showNotes) NotesButton(actions: actions, color: color),
          if (showHighlights) HighlightsButton(actions: actions, color: color),
          if (showBookmarks) BookmarkButton(actions: actions, color: color),
          if (showJumpToPage) JumpToPageButton(actions: actions, color: color),
          if (showAppearance) AppearanceButton(actions: actions, color: color),
          if (showReadingSettings)
            ReadingSettingsButton(actions: actions, color: color),
        ],
      );
}
