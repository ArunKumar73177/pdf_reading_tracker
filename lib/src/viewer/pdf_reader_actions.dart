import 'package:flutter/foundation.dart';

import '../theme/appearance_mode.dart';
import 'pdf_reading_tracker_viewer.dart';

/// Public facade exposing the reader actions and live counts that power
/// [PdfReadingTrackerViewer]'s built-in app bar and bookmark FAB.
///
/// Obtain via `PdfReadingTrackerViewerState.readerActions` (attach a
/// `GlobalKey<PdfReadingTrackerViewerState>` to the viewer). Every method
/// here forwards directly into the same handler the plugin's own chrome
/// uses — no business logic is duplicated.
///
/// Prefer the ready-made [BookmarkButton] / [NotesButton] /
/// [HighlightsButton] / [SearchButton] / [JumpToPageButton] /
/// [AppearanceButton] / [ReadingSettingsButton] / [PdfReaderToolbar]
/// widgets (in `pdf_reader_toolbar.dart`) over calling this manually —
/// they already wire up live counts/icons via [listenable].
@immutable
class PdfReaderActions {
  const PdfReaderActions(this._state);

  final PdfReadingTrackerViewerState _state;

  /// Notifies on any change relevant to a custom toolbar.
  Listenable get listenable => _state.readerListenable;

  int get bookmarkCount => _state.bookmarkCount;
  int get highlightCount => _state.highlightCount;
  int get noteCount => _state.noteCount;
  bool get searchVisible => _state.searchVisible;
  bool get isBookmarkedOnCurrentPage => _state.isBookmarkedOnCurrentPage;
  AppearanceMode get appearanceMode => _state.appearanceMode;
  int get currentPage => _state.currentPage;
  int get totalPages => _state.totalPages;

  Future<void> addOrEditBookmark() => _state.handleBookmarkTap();
  Future<void> showBookmarks() => _state.handleBookmarksIconTap();
  Future<void> showHighlights() => _state.handleHighlightsIconTap();
  Future<void> showNotes() => _state.handleNotesIconTap();
  Future<void> addNote() => _state.handleAddNoteTap();
  Future<void> jumpToPage() => _state.handleJumpToPage();
  Future<void> showAppearanceSelector() =>
      _state.showAppearanceSelectorAction();
  Future<void> showReadingSettings() => _state.showReadingSettingsAction();
  void toggleSearch() => _state.toggleSearchAction();
}
