# pdf_reading_tracker

[![pub package](https://img.shields.io/pub/v/pdf_reading_tracker.svg)](https://pub.dev/packages/pdf_reading_tracker)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](#platform-support)

A production-ready Flutter PDF reader widget, built on **Syncfusion PDF Viewer**, with reading progress tracking, bookmarks, text-anchored notes, annotations, appearance theming, and local SQLite persistence — fully offline-first.

Designed for educational apps, document-centric productivity tools, and any app that needs a drop-in, stateful PDF reading experience without building the plumbing yourself.

---

## Table of Contents

- [Features](#features)
- [Platform Support](#platform-support)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Widget Configuration](#widget-configuration)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Storage](#storage)
- [Offline Support](#offline-support)
- [Performance](#performance)
- [Example App](#example-app)
- [Roadmap](#roadmap)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Category | Capabilities |
|---|---|
| **Reading** | High-quality rendering, progress tracking, continue-reading, recent PDFs, jump-to-page, multi-PDF support, double-tap zoom, vertical/horizontal navigation |
| **Search** | In-document text search, match navigation, result highlighting |
| **Bookmarks** | Add/remove bookmarks, per-bookmark notes, SQLite persistence |
| **Annotations** | Highlight, underline, strikethrough, squiggly — with full persistence and restoration |
| **Notes** | Text-anchored notes, edit/delete, jump-to-note, persistent storage |
| **Appearance** | Light / Dark / Follow-System theming with an in-reader appearance selector |
| **Reading Comfort** | Immersive (distraction-free) reading mode with auto-hiding chrome, keep-screen-awake toggle |
| **PDF Management** | Import from device storage, persistent library, continue-reading & recent dashboards, auto-restore after app restart |
| **PDF Operations** | Merge multiple PDFs, split into smaller documents, typed exception handling |
| **Storage** | SQLite persistence, offline-first, automatic temp-file cleanup |

<details>
<summary><strong>Full feature breakdown</strong></summary>

### Reading
- High-quality PDF rendering using Syncfusion PDF Viewer
- Reading progress tracking with persistent position
- Continue-reading and recently-read dashboards
- Jump to any page
- Multi-PDF support
- Double-tap zoom
- Vertical and horizontal (swipe) page navigation

### Search
- Built-in PDF text search
- Navigate between matches
- Match highlighting

### Bookmarks
- Add and remove bookmarks
- Attach notes to bookmarks
- SQLite-backed persistence

### Annotations
- Highlight, underline, strikethrough, and squiggly annotation types
- Six-color palette per annotation
- Full persistence and restoration after restart

### Notes
- Text-anchored notes (linked to the exact selected text and its position)
- Edit and delete
- Jump directly to the page a note was created on
- Persistent storage independent of annotations

### Appearance & Reading Comfort
- Light, Dark, and Follow-System appearance modes with an in-reader selector sheet
- Immersive reading mode: auto-hiding app bar/controls, toggled by a single tap
- Optional keep-screen-awake while reading

### PDF Management
- Import PDFs from device storage
- Persistent, on-device PDF library
- Continue-reading and recent-PDFs dashboards
- Automatic restoration after app restart

### PDF Operations
- Merge multiple PDFs into one document
- Split a PDF into smaller documents by page count
- Typed exceptions for merge/split failure modes

### Storage
- SQLite persistence, offline-first
- Lightweight, migration-based schema
- Automatic cleanup of temporary imported/merged/split files

</details>

---

## Platform Support

| Android | iOS |
|:---:|:---:|
| ✅ | ✅ |

---

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  pdf_reading_tracker: ^4.0.1
```

Then fetch it:

```bash
flutter pub get
```

Import it wherever you need it:

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

---

## Quick Start

The fastest way to get a fully working reader — progress tracking, bookmarks, highlights, and notes all included — is to drop in the viewer widget:

```dart
PdfReadingTrackerViewer(
  pdfId: 'clean_architecture',
  pdfTitle: 'Clean Architecture',
  assetPath: 'assets/pdfs/clean_architecture.pdf',
)
```

That's it — reading progress, bookmarks, highlights, and notes are automatically tracked and persisted for this `pdfId`.

### Reading a user-picked file instead of a bundled asset

```dart
PdfReadingTrackerViewer(
  pdfId: 'user_document_42',
  pdfTitle: 'My Document',
  filePath: '/data/user/0/.../user_pdfs/document_42.pdf',
)
```

> Provide **exactly one** of `assetPath` or `filePath` — not both, and not neither.

---

## Widget Configuration

`PdfReadingTrackerViewer` exposes the following parameters:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `pdfId` | `String` | required | Stable, unique identifier for this PDF (used as the persistence key) |
| `pdfTitle` | `String` | required | Display title shown in the app bar |
| `assetPath` | `String?` | — | Path to a bundled asset PDF. Mutually exclusive with `filePath` |
| `filePath` | `String?` | — | Path to a PDF on device storage. Mutually exclusive with `assetPath` |
| `onPageChanged` | `void Function(int page, int total)?` | — | Called whenever the current page changes |
| `theme` | `PdfViewerTheme?` | — | Optional host-app color overrides for the app bar |
| `swipeHorizontal` | `bool` | `false` | Horizontal (paged) vs. vertical (continuous scroll) navigation |
| `enableDoubleTap` | `bool` | `true` | Enable double-tap-to-zoom |
| `showAppBar` | `bool` | `true` | Show/hide the reader's app bar |
| `showBottomBar` | `bool` | `true` | Show/hide the bottom progress overlay |
| `showBookmarkFab` | `bool` | `true` | Show/hide the floating bookmark/note buttons |
| `enableSearch` | `bool` | `true` | Enable in-document text search |
| `enableHighlight` | `bool` | `true` | Enable highlight/annotation creation |
| `showAppearanceToggle` | `bool` | `true` | Show the Light/Dark/System appearance option |
| `initialAppearanceMode` | `AppearanceMode` | `AppearanceMode.system` | Starting appearance mode |
| `onAppearanceModeChanged` | `void Function(AppearanceMode mode)?` | — | Called when the user changes appearance mode |
| `initialReadingSettings` | `ReadingSettings?` | — | Starting immersive-mode / reading-comfort preferences |
| `showReadingSettingsToggle` | `bool` | `true` | Show the reading-settings (immersive mode, keep-awake) option |
| `onReadingSettingsChanged` | `void Function(ReadingSettings settings)?` | — | Called when reading settings change |

### Fully configured example

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

  showAppearanceToggle: true,
  showReadingSettingsToggle: true,
)
```

---

## API Reference

Beyond the widget, a static `PdfReadingTracker` facade exposes every capability programmatically — useful for dashboards, background sync, or building your own reader UI.

### Reading Progress

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

// Get progress for a specific PDF
final progress = await PdfReadingTracker.getProgress('flutter_notes');

// Get recently-read PDFs
final recent = await PdfReadingTracker.getRecentlyRead();
```

### Bookmarks

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

### Highlights

```dart
final highlights = await PdfReadingTracker.getHighlights('flutter_notes');
```

### Notes

```dart
final notes = await PdfReadingTracker.getNotes('flutter_notes');
```

### Search

Search is built directly into `PdfReadingTrackerViewer` via `enableSearch: true` — it provides in-document text search with match navigation and result highlighting, no extra wiring required.

### Importing a PDF

```dart
final picked = await PdfPickerService.pickPdf();
```

### Merging PDFs

```dart
final mergedPdf = await PdfMergeService.merge(
  inputPaths: [pdf1, pdf2, pdf3],
);
```

### Splitting a PDF

```dart
final files = await PdfSplitService.split(
  pdfPath: sourcePdf,
  pagesPerFile: 25,
);
```

---

## Architecture

- **Rendering** — Syncfusion PDF Viewer for on-device rendering and text selection
- **PDF processing** — Syncfusion PDF processing engine for merge/split operations
- **Persistence** — a dedicated SQLite layer, offline-first by design
- **Service-based separation** — reading progress, bookmarks, annotations, and notes are each handled by their own service, avoiding a monolithic data layer
- **Appearance/immersive layer** — a lightweight, listenable-based theming and visibility controller layer that never forces a rebuild of the PDF surface itself

---

## Storage

- Lightweight, migration-based SQLite schema
- Efficient annotation and note storage (multi-rect selections stored per annotation/note)
- Automatic cleanup of temporary files created during import, merge, or split operations
- No cloud sync or network dependency — everything lives on-device

---

## Offline Support

`pdf_reading_tracker` is fully offline-first: reading progress, bookmarks, highlights, and notes are all persisted locally via SQLite. No network connection is required for any feature in the package.

---

## Performance

- Background isolate-based page-geometry reads to avoid UI jank on large documents
- Debounced progress persistence to minimize redundant database writes
- Appearance and reading-settings changes are isolated via scoped `ListenableBuilder`s so the PDF surface itself never rebuilds during a theme transition

---

## Example App

The `example/` app demonstrates the full feature set end-to-end: PDF reading, progress tracking, continue-reading, recent PDFs, bookmarks, notes, highlights, appearance switching, immersive reading mode, PDF import, merge, and split.

---

## Roadmap

- Further refinement of dominant/exact page detection accuracy
- Expanded search customization options
- Additional annotation types

---

## Known Limitations

- Reading progress relies on Syncfusion page-change events combined with visible-area detection; exact dominant-page accuracy is still being refined.
- Native swipe-threshold page snapping is not yet implemented (pending a future Syncfusion viewer upgrade).

---

## Contributing

Contributions are welcome. Please open an issue to discuss significant changes before submitting a pull request.

- **Issues & feature requests:** [GitHub Issues](https://github.com/ArunKumar73177/pdf_reading_tracker/issues)
- **Pull requests:** fork the repository, create a feature branch, and submit a PR against `main`.

---

## License

MIT License