# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## 5.0.0

This release consolidates a series of internal stability, architecture, and reliability passes made since 4.1.0. The public API is unchanged from 4.1.0 — this is a production-hardening release, not a rewrite of the surface developers integrate against.

### Added
- `ImmersiveChromeVisibility` widget for host apps (`showAppBar: false`) to keep their own app bar or toolbar hidden/shown in lockstep with the plugin's immersive chrome, without manually listening to internal state.

### Changed
- Reader app bar redesigned around a calmer, Material 3 style: neutral surface background instead of a saturated fill, softly rounded bottom corners, refined title typography, and explicit rounded touch targets for every action icon.
- Reader toolbar decluttered: Search, Notes, Highlights, and Bookmarks remain always visible; Jump to Page, Appearance, and Reading Settings moved into a single overflow menu. No functionality was removed — every action remains one or two taps away, using the same callbacks and public API as before.
- The floating action buttons (bookmark/add note) now animate with a scale-and-fade transition instead of a directional slide, to visually distinguish them from the app bar's slide-from-top and the progress overlay's slide-from-bottom.

### Improved
- Scaffold selection (immersive vs. classic layout) and immersive chrome-visibility now share a single merged `Listenable`, eliminating a narrow window where the two could be evaluated against slightly stale state relative to each other.
- Appearance changes now reach the background painted behind the PDF surface (including the spacing gaps between pages) without ever reconstructing the `SfPdfViewer` widget itself.
- `showAppBar: false` integrations now also receive the bookmark/add-note floating action buttons, manually positioned in the conventional bottom-right location, matching behavior previously available only with the built-in app bar.
- Resolved a `BuildContext` lifecycle issue (`use_build_context_synchronously`) in the bookmark and add-note dialog flows by guarding post-`await` context usage on the specific `BuildContext` instance involved, rather than only the widget's own `mounted` flag.

### Fixed
- Progress overlay (bottom pill) no longer silently loses its bottom-pinned position due to `Positioned` being nested behind other widgets instead of sitting directly under its parent `Stack`.
- Progress overlay no longer runs its own independent auto-hide timer; visibility is now driven by the same immersive-chrome signal used by the app bar and FAB, so it no longer fades out unexpectedly with Immersive Mode off.
- Appearance selector menu no longer opens outside the reader's local theme scope, which previously caused it to render with the host app's ambient colors instead of the reader's own resolved appearance.
- Resolved compile-time regressions from an internal refactor (a non-existent state getter reference and two phantom public exports).

---

## 4.1.0

### Added
- Host toolbar integration — `PdfReadingTrackerViewer` can hand off all of its chrome to a host app instead of rendering its own app bar.
- `showAppBar: false` support, allowing the reader to be embedded under a host-supplied `AppBar` or custom toolbar.
- Public `PdfReadingTrackerViewerState`, exposing reader control points to host widgets via a `GlobalKey`.
- `PdfReaderActions` API and `readerActions` accessor for triggering reader actions (bookmark, note, search, appearance, reading settings, jump-to-page) from outside the widget.
- `readerListenable`, a `Listenable` for reflecting live reader state in host-supplied UI.
- `PdfReaderToolbar`, a ready-made toolbar widget rendering the full set of reader controls.
- Prebuilt toolbar button widgets for host app bar and toolbar composition:
    - `BookmarkButton`
    - `NotesButton`
    - `HighlightsButton`
    - `SearchButton`
    - `AppearanceButton`
    - `ReadingSettingsButton`
    - `JumpToPageButton`
- Public exports for all host toolbar integration types.

### Improved
- Better integration with applications using custom app bars.
- Better API documentation across the host-integration surface.

### Internal
- Code cleanup.
- Public API organization.

### Breaking Changes
- None.

---

## 4.0.2

### Changed
- Simplified package metadata and improved pub.dev discoverability.
- Refined README with clearer setup instructions, feature descriptions, and API documentation.

### Fixed
- Resolved all dartdoc unresolved documentation references.
- Improved lower-bound package compatibility for pub.dev analysis.
- Cleaned up analyzer and documentation issues.

### Internal
- Updated package metadata and release documentation.

---

## 4.0.1

Continued evolution of the package's appearance system, page-detection engine, and annotation reliability introduced in 3.0.0.

### Added
- Full Light / Dark / Follow-System appearance mode.
- `ReaderColors` theme extension and centralized design tokens.
- Appearance selector sheet with a Material 3 segmented control.

### Improved
- Two-layer page detection engine: exact visible-area detection using real per-page aspect ratios, with a uniform-height midpoint fallback.
- Auto-hiding progress overlay after page changes.
- Scoped `ListenableBuilder` usage in place of broad `setState` calls, reducing unnecessary rebuilds.

### Fixed
- Redundant note button that duplicated the post-commit note workflow.
- Notes saving against the wrong page (now authoritative on the text line's page number rather than scroll heuristics).
- Search compile error caused by an invalid `TextSearchOption` value.
- Progress overlay flicker (converted to a timer-free stateless widget).
- Page-change race condition between `NotificationListener` and Syncfusion's internal state.
- Missing visual indicators for annotated highlights that have notes attached.
- Excessive rebuilds caused by overly broad `Listenable.merge` scopes.

### Internal
- Resolved resource leak risks across controllers and focus nodes.
- Resolved `flutter analyze` deprecation warnings, including deprecated `withOpacity` usages.

### Breaking Changes
- None. Existing integrations using `PdfReadingTrackerViewer` and the static `PdfReadingTracker` API continue to work without modification.

---

## 3.0.0

Complete migration to Syncfusion PDF Viewer, expanding the package from a reading-progress tracker into a full-featured PDF reader and annotation solution.

### Major Architecture Changes
- Replaced ALH PDF View with Syncfusion PDF Viewer.
- Reworked PDF rendering architecture.
- Simplified dependency management by removing JitPack requirements.

### Added

**PDF Reading**
- Reading progress tracking, Continue Reading, Recent PDFs, jump-to-page, multi-PDF support, persistent reading position.

**User PDF Management**
- Import PDFs from device storage, persistent PDF library, stable PDF ID generation, automatic restoration after app restart.

**Search**
- Built-in PDF text search, search navigation, result highlighting.

**Bookmarks**
- Bookmark creation, removal, notes, persistent storage.

**Annotations**
- Highlight, underline, strikethrough, and squiggly annotations, with persistence and restoration.

**Notes**
- Text-linked notes, edit, delete, jump to note, persistent storage.

**PDF Operations**
- PDF merge, PDF split, typed exception handling.

### Fixed
- File Not Found issues caused by temporary file picker paths.
- Reading progress persistence issues.
- Bookmark and annotation restoration issues.
- Dialog and `TextEditingController` lifecycle issues.
- Duplicate PDF cache storage.

### Storage Optimizations
- Automatic cleanup of temporary imported PDFs.
- Lightweight SQLite schema.

---

## 2.1.0

### Added
- User PDF upload support using File Picker.
- Continue Reading dashboard and Recent PDFs screen.
- Persistent storage of user-selected PDFs, with stable PDF ID generation for user, merged, and split PDFs.
- Automatic resume-from-last-page support for uploaded PDFs.
- Jump-to-page navigation.
- Bookmark support on uploaded, merged, and split PDFs.

### Fixed
- File Not Found issues caused by temporary File Picker cache paths.
- Reading progress never reaching 100% on the final page.
- Page 1 showing 0% progress.
- Continue Reading and Recent PDFs display and filtering issues.
- Bookmark persistence issues for generated PDFs.

### Internal
- Added `PdfPickerService` and `PdfIdHelper`.
- Extended database schema to support user-selected PDFs.