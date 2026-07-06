# pdf_reading_tracker

A production-ready Flutter PDF reader package powered by Syncfusion PDF Viewer.

Track reading progress, continue reading from where users left off, manage bookmarks, create annotations, attach text-linked notes, import PDFs from device storage, merge and split PDFs, and persist everything locally using SQLite.

Designed for educational, productivity, and document-centric applications.

---

## Features

| Category | Capabilities |
|---|---|
| PDF Reading | High-quality rendering, progress tracking, continue reading, recent PDFs, jump-to-page, multi-PDF support, double-tap zoom, vertical/horizontal navigation |
| Search | Built-in text search, search navigation, match highlighting |
| Bookmarks | Add/remove bookmarks, bookmark notes, SQLite-backed persistence |
| Annotations | Highlight, underline, strikethrough, squiggly, full persistence and restoration |
| Notes | Text-linked notes, edit/delete, jump-to-note, persistent storage |
| PDF Management | Import from device, persistent library, continue-reading & recent dashboards, auto-restore after restart |
| PDF Operations | Merge, split, typed exception handling |
| Storage | SQLite persistence, offline-first, temporary cache cleanup |

### PDF Reading
- High-quality PDF rendering using Syncfusion PDF Viewer
- Reading progress tracking
- Continue reading
- Recent PDFs
- Jump to page
- Multi-PDF support
- Double-tap zoom
- Vertical and horizontal navigation
- Persistent reading position

### Search
- Built-in PDF text search
- Search navigation
- Match highlighting

### Bookmarks
- Add bookmarks
- Remove bookmarks
- Bookmark notes
- Bookmark persistence
- SQLite-backed storage

### Annotations
- Highlight
- Underline
- Strikethrough
- Squiggly
- Annotation persistence
- Annotation restoration after restart

### Notes
- Text-linked notes
- Edit notes
- Delete notes
- Jump to note
- Persistent storage

### User PDF Management
- Import PDFs from device storage
- Persistent PDF library
- Continue reading dashboard
- Recent PDFs dashboard
- Automatic restoration after app restart

### PDF Operations
- Merge multiple PDFs
- Split PDFs into smaller documents
- Typed exception handling
- Syncfusion PDF processing

### Storage
- SQLite persistence
- Offline first
- Lightweight database
- Persistent PDF storage
- Temporary cache cleanup
- Storage-efficient architecture

---

## Platform Support

| Android | iOS |
|---|---|
| ✅ | ✅ |

---

## Installation

```yaml
dependencies:
  pdf_reading_tracker: ^4.0.0
```

---

## Import

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

---

## Quick Start

```dart
PdfReadingTrackerViewer(
  pdfId: 'clean_architecture',
  pdfTitle: 'Clean Architecture',
  assetPath: 'assets/pdfs/clean_architecture.pdf',
)
```

---

## Complete Widget Example

```dart
PdfReadingTrackerViewer(
  pdfId: 'flutter_notes',
  pdfTitle: 'Flutter Notes',
  assetPath: 'assets/pdfs/flutter_notes.pdf',

  showAppBar: true,
  showBottomBar: true,
  showBookmarkFab: true,

  enableSearch: true,
  enableHighlight: true,

  swipeHorizontal: false,
  enableDoubleTap: true,
)
```

### Configuration

| Parameter | Type | Default | Description |
|---|---|---|---|
| `pdfId` | `String` | required | Stable unique identifier for this PDF |
| `pdfTitle` | `String` | required | Display title shown in the app bar |
| `assetPath` | `String` | required | Path to the bundled or imported PDF |
| `showAppBar` | `bool` | `true` | Show/hide the reader's app bar |
| `showBottomBar` | `bool` | `true` | Show/hide the bottom navigation bar |
| `showBookmarkFab` | `bool` | `true` | Show/hide the floating bookmark button |
| `enableSearch` | `bool` | `true` | Enable in-document text search |
| `enableHighlight` | `bool` | `true` | Enable highlight annotations |
| `swipeHorizontal` | `bool` | `false` | Horizontal vs. vertical page navigation |
| `enableDoubleTap` | `bool` | `true` | Enable double-tap-to-zoom |

---

## Reading Progress API

```dart
// Save progress
await PdfReadingTracker.saveProgress(
  ReadingProgress.create(
    pdfId: 'flutter_notes',
    currentPage: 25,
    totalPages: 100,
    title: 'Flutter Notes',
  ),
);

// Get progress
final progress = await PdfReadingTracker.getProgress('flutter_notes');

// Get recently read
final recent = await PdfReadingTracker.getRecentlyRead();
```

---

## Bookmarks API

```dart
await PdfReadingTracker.addBookmark(
  Bookmark.create(
    pdfId: 'flutter_notes',
    page: 25,
    note: 'Important topic',
  ),
);

final bookmarks = await PdfReadingTracker.getBookmarks('flutter_notes');
```

---

## Highlights API

```dart
final highlights = await PdfReadingTracker.getHighlights('flutter_notes');
```

---

## Notes API

```dart
final notes = await PdfReadingTracker.getNotes('flutter_notes');
```

---

## Search API

Search is available directly on `PdfReadingTrackerViewer` via `enableSearch: true`, exposing in-document text search with navigation between matches and highlighted results.

---

## PDF Import

```dart
final picked = await PdfPickerService.pickPdf();
```

---

## PDF Merge

```dart
final mergedPdf = await PdfMergeService.merge(
  inputPaths: [pdf1, pdf2, pdf3],
);
```

---

## PDF Split

```dart
final files = await PdfSplitService.split(
  pdfPath: sourcePdf,
  pagesPerFile: 25,
);
```

---

## Architecture

- Syncfusion PDF Viewer for rendering
- Syncfusion PDF processing for merge/split
- SQLite persistence layer
- Offline-first design
- Service-based architecture separating reading, bookmarks, annotations, and notes

## Storage

- SQLite-backed, lightweight schema
- Efficient annotation and note storage
- Automatic cleanup of temporary imported PDFs

## Performance

- Background isolate-based page geometry reads to avoid UI jank
- Debounced progress persistence to minimize database writes

## Offline Support

Fully offline-first — all reading progress, bookmarks, highlights, and notes are persisted locally via SQLite with no network dependency.

---

## Example App

The `example/` app demonstrates the full feature set: PDF reading, progress tracking, continue reading, recent PDFs, bookmarks, notes, highlights, PDF import, merge, and split.

---

## Roadmap

- Dominant/exact page detection improvements
- Expanded search customization
- Additional annotation types

---

## Contributing

Issues and pull requests are welcome via the [issue tracker](https://github.com/ArunKumar73177/pdf_reading_tracker/issues).

---

## Known Limitations

- Reading progress relies on Syncfusion page-change events combined with visible-area detection; exact dominant-page accuracy is being refined.
- Native swipe-threshold page snapping is not yet implemented (tracked for a future release pending a Syncfusion viewer upgrade).

---

## License

MIT License