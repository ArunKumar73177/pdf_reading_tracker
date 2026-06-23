# pdf_reading_tracker

A production-ready Flutter PDF reader package powered by Syncfusion PDF Viewer.

Track reading progress, continue reading from where users left off, manage bookmarks, create annotations, attach text-linked notes, import PDFs from device storage, merge and split PDFs, and persist everything locally using SQLite.

Designed for educational, productivity, and document-centric applications.

---

## Features

### PDF Reading

* High-quality PDF rendering using Syncfusion PDF Viewer
* Reading Progress Tracking
* Continue Reading
* Recent PDFs
* Jump To Page
* Multi-PDF Support
* Double-Tap Zoom
* Vertical and Horizontal Navigation
* Persistent Reading Position

### Search

* Built-in PDF Text Search
* Search Navigation
* Match Highlighting

### Bookmarks

* Add Bookmarks
* Remove Bookmarks
* Bookmark Notes
* Bookmark Persistence
* SQLite-backed Storage

### Annotations

* Highlight
* Underline
* Strikethrough
* Squiggly
* Annotation Persistence
* Annotation Restoration After Restart

### Notes

* Text-linked Notes
* Edit Notes
* Delete Notes
* Jump To Note
* Persistent Storage

### User PDF Management

* Import PDFs From Device Storage
* Persistent PDF Library
* Continue Reading Dashboard
* Recent PDFs Dashboard
* Automatic Restoration After App Restart

### PDF Operations

* Merge Multiple PDFs
* Split PDFs Into Smaller Documents
* Typed Exception Handling
* Syncfusion PDF Processing

### Storage

* SQLite Persistence
* Offline First
* Lightweight Database
* Persistent PDF Storage
* Temporary Cache Cleanup
* Storage Efficient Architecture

---

## Platform Support

| Android | iOS |
| ------- | --- |
| ✅       | ✅   |

---

## Installation

```yaml
dependencies:
  pdf_reading_tracker: ^3.0.0
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

## Reader Widget

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

---

## Reading Progress API

### Save Progress

```dart
await PdfReadingTracker.saveProgress(
  ReadingProgress.create(
    pdfId: 'flutter_notes',
    currentPage: 25,
    totalPages: 100,
    title: 'Flutter Notes',
  ),
);
```

### Get Progress

```dart
final progress =
    await PdfReadingTracker.getProgress('flutter_notes');
```

### Get Recently Read

```dart
final recent =
    await PdfReadingTracker.getRecentlyRead();
```

---

## Bookmark API

### Add Bookmark

```dart
await PdfReadingTracker.addBookmark(
  Bookmark.create(
    pdfId: 'flutter_notes',
    page: 25,
    note: 'Important topic',
  ),
);
```

### Get Bookmarks

```dart
final bookmarks =
    await PdfReadingTracker.getBookmarks('flutter_notes');
```

---

## Highlight API

```dart
final highlights =
    await PdfReadingTracker.getHighlights('flutter_notes');
```

---

## Notes API

```dart
final notes =
    await PdfReadingTracker.getNotes('flutter_notes');
```

---

## PDF Import

```dart
final picked =
    await PdfPickerService.pickPdf();
```

---

## PDF Merge

```dart
final mergedPdf =
    await PdfMergeService.merge(
      inputPaths: [
        pdf1,
        pdf2,
        pdf3,
      ],
    );
```

---

## PDF Split

```dart
final files =
    await PdfSplitService.split(
      pdfPath: sourcePdf,
      pagesPerFile: 25,
    );
```

---

## Example Application

The package includes a complete example application demonstrating:

* PDF Reader
* Reading Progress
* Continue Reading
* Recent PDFs
* Bookmarks
* Notes
* Highlights
* PDF Import
* PDF Merge
* PDF Split

---

## Architecture

* Syncfusion PDF Viewer
* Syncfusion PDF Processing
* SQLite Persistence
* Offline-First Design
* Service-Based Architecture
* Production-Ready Structure

---

## Known Limitations

* Reading progress currently relies on Syncfusion page-change events.
* Dominant page detection is planned for a future release.

---

## License

MIT License
