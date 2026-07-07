# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog.

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
- Full Light / Dark / Follow-System appearance mode
- `ReaderColors` theme extension and centralized design tokens
- Appearance selector sheet with a Material 3 segmented control

### Improved
- Two-layer page detection engine: exact visible-area detection using real per-page aspect ratios, with a uniform-height midpoint fallback
- Auto-hiding progress overlay after page changes
- Scoped `ListenableBuilder` usage in place of broad `setState` calls, reducing unnecessary rebuilds

### Fixed
- Redundant note button that duplicated the post-commit note workflow
- Notes saving against the wrong page (now authoritative on the text line's page number rather than scroll heuristics)
- Search compile error caused by an invalid `TextSearchOption` value
- Progress overlay flicker (converted to a timer-free stateless widget)
- Page-change race condition between `NotificationListener` and Syncfusion's internal state
- Missing visual indicators for annotated highlights that have notes attached
- Excessive rebuilds caused by overly broad `Listenable.merge` scopes

### Internal
- Resolved resource leak risks across controllers and focus nodes
- Resolved `flutter analyze` deprecation warnings, including deprecated `withOpacity` usages

### Migration Notes
No public API changes. Existing integrations using `PdfReadingTrackerViewer` and the static `PdfReadingTracker` API continue to work without modification.

### Breaking Changes
None.

### Known Limitations
- Dominant page detection continues to rely on a combination of page-change events and geometry heuristics; further refinement is ongoing.
- Native swipe-threshold page snapping is not yet available.

---

## 3.0.0
[... existing 3.0.0 entry unchanged below this line ...]