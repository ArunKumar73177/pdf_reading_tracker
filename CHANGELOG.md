# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
- Better host application integration overall.

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
- Improved package documentation for better developer experience.

### Fixed
- Resolved all dartdoc unresolved documentation references.
- Improved lower-bound package compatibility for pub.dev analysis.
- Cleaned up analyzer and documentation issues.
- Minor code quality and maintainability improvements.

### Internal
- Updated package metadata and release documentation.
- General maintenance and project cleanup.

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

### Known Limitations
- Dominant page detection continues to rely on a combination of page-change events and geometry heuristics; further refinement is ongoing.
- Native swipe-threshold page snapping is not yet available.

---

## 3.0.0

This release introduces a complete migration to Syncfusion PDF Viewer and significantly expands the package from a reading-progress tracker into a full-featured PDF reader and annotation solution.

### Major Architecture Changes
- Replaced ALH PDF View with Syncfusion PDF Viewer.
- Reworked PDF rendering architecture.
- Improved rendering reliability and maintainability.
- Simplified dependency management by removing JitPack requirements.
- Improved overall package structure for long-term scalability.

### Added

**PDF Reading**
- Reading progress tracking.
- Continue Reading.
- Recent PDFs dashboard.
- Jump-to-page navigation.
- Multi-PDF support.
- Persistent reading position.

**User PDF Management**
- Import PDFs from device storage.
- Persistent PDF library.
- Stable PDF ID generation.
- Automatic PDF restoration after app restart.

**Search**
- Built-in PDF text search.
- Search navigation.
- Search result highlighting.

**Bookmarks**
- Bookmark creation.
- Bookmark removal.
- Bookmark notes.
- Persistent bookmark storage.

**Annotations**
- Highlight annotations.
- Underline annotations.
- Strikethrough annotations.
- Squiggly annotations.
- Annotation persistence.
- Annotation restoration.

**Notes**
- Text-linked notes.
- Edit notes.
- Delete notes.
- Jump to note.
- Persistent note storage.

**PDF Operations**
- PDF merge.
- PDF split.
- Typed exception handling.

### Improved
- Improved reading progress tracking.
- Improved Continue Reading experience.
- Improved Recent PDFs workflow.
- Improved PDF loading performance.
- Improved bookmark management.
- Improved annotation restoration.
- Improved database structure.
- Improved storage efficiency.
- Improved offline persistence.
- Improved user PDF workflow.

### Fixed
- Fixed File Not Found issues caused by temporary file picker paths.
- Fixed reading progress persistence issues.
- Fixed bookmark restoration issues.
- Fixed PDF reopening issues.
- Fixed annotation restoration race conditions.
- Fixed dialog lifecycle issues.
- Fixed `TextEditingController` disposal issues.
- Fixed duplicate PDF cache storage.
- Fixed multiple persistence edge cases.

### Storage Optimizations
- Automatic cleanup of temporary imported PDFs.
- Reduced duplicate file storage.
- Lightweight SQLite schema.
- Efficient annotation storage.
- Efficient note storage.

### Internal
- Added Highlight APIs.
- Added Note APIs.
- Added Search Controller.
- Added Annotation Infrastructure.
- Extended SQLite schema.
- Improved service architecture.
- Improved persistence layer.

### Known Limitations
- Reading progress currently relies on Syncfusion page-change events.
- Dominant page detection is planned for a future release.
- Advanced search customization may be expanded in future versions.

---

## 2.1.0

### Added
- User PDF upload support using File Picker.
- Continue Reading dashboard.
- Recent PDFs screen.
- Persistent storage of user-selected PDFs.
- Stable PDF ID generation for user, merged, and split PDFs.
- Automatic resume-from-last-page support for uploaded PDFs.
- Jump-to-page navigation.
- Improved progress tracking across all PDF types.
- Bookmark support on uploaded PDFs.
- Bookmark support on merged PDFs.
- Bookmark support on split PDFs.

### Improved
- Improved PDF loading workflow.
- Improved reading progress calculation accuracy.
- Improved persistence of user-selected PDFs across app restarts.
- Improved Continue Reading and Recent PDFs experience.
- Improved SQLite data handling and PDF identification.
- Enhanced example application with a multi-PDF workflow.

### Fixed
- Fixed File Not Found issues caused by temporary File Picker cache paths.
- Fixed reading progress never reaching 100% on the final page.
- Fixed page 1 showing 0% progress.
- Fixed Continue Reading not displaying newly opened PDFs.
- Fixed Recent PDFs filtering issues.
- Fixed progress tracking inconsistencies for merged and split PDFs.
- Fixed bookmark persistence issues for generated PDFs.
- Reduced lag during page jump navigation.
- Improved PDF reopening and restoration behavior.

### Internal
- Added `PdfPickerService`.
- Added `PdfIdHelper`.
- Extended database schema to support user-selected PDFs.
- Optimized controller initialization and persistence workflow.
- Improved package architecture in preparation for future features, including text search, text highlighting, PDF annotation, page extraction, page rotation, password-protected PDFs, and thumbnail navigation.