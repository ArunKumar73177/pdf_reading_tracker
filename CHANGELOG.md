## 2.0.0

### Breaking changes
- None — all existing `PdfReadingTracker.*` static calls work unchanged.

### New features
- Added `PdfReadingTrackerViewer` widget: complete drop-in PDF reader.
- Added `PdfViewerTheme` for app bar and progress bar colour customisation.
- Added `showAppBar`, `showBottomBar`, `showBookmarkFab` flags for embedding.
- Integrated `alh_pdf_view` as a package dependency — consumers no longer
  need to add it separately.
- Automatic FK-anchor creation prevents silent bookmark INSERT failures on
  first launch.

### Internal
- Added `PdfViewerController` (internal), `ReaderBottomBar`, `BookmarkFab`,
  `BookmarksSheet` widgets — all private, not exported.

## 1.0.0

- Initial release: SQLite-backed reading progress tracking and bookmark
  management.