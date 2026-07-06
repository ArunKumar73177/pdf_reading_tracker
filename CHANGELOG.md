## 4.0.0

### 🚀 Major Release

Continued evolution of the package's appearance system, page-detection engine, and annotation reliability introduced in 3.0.0.

### ✨ Added

- Full Light / Dark / Follow-System appearance mode
- `ReaderColors` theme extension and centralized design tokens
- Appearance selector sheet with Material 3 segmented control

### ⚡ Improvements

- Two-layer page detection engine: exact visible-area detection using real per-page aspect ratios, with a uniform-height midpoint fallback
- Auto-hiding progress overlay after page changes
- Scoped `ListenableBuilder` usage in place of broad `setState` calls to reduce rebuilds

### 🛠 Fixed

- Redundant note button duplicating the post-commit workflow
- Notes saving against the wrong page (now authoritative on the text line's page number rather than scroll heuristics)
- Search compile error from an invalid `TextSearchOption` value
- Progress overlay flicker (converted to a timer-free stateless widget)
- Page-change race condition between `NotificationListener` and Syncfusion state
- Missing visual indicators for annotated highlights with notes
- Excessive rebuilds from overly broad `Listenable.merge` scopes
- Resource leak risks across controllers and focus nodes
- `flutter analyze` deprecation warnings (including `withOpacity` usages)

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