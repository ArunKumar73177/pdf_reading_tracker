# pdf_reading_tracker

[![pub package](https://img.shields.io/pub/v/pdf_reading_tracker.svg)](https://pub.dev/packages/pdf_reading_tracker)
[![pub points](https://img.shields.io/pub/points/pdf_reading_tracker)](https://pub.dev/packages/pdf_reading_tracker/score)
[![popularity](https://img.shields.io/pub/popularity/pdf_reading_tracker)](https://pub.dev/packages/pdf_reading_tracker/score)
[![likes](https://img.shields.io/pub/likes/pdf_reading_tracker)](https://pub.dev/packages/pdf_reading_tracker/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](#platform-support)

A stateful Flutter PDF reader widget with reading progress tracking, bookmarks, notes, annotations, appearance theming, and offline-first SQLite persistence — built on Syncfusion PDF Viewer.

## Why pdf_reading_tracker?

Building a PDF reading experience usually means wiring together a viewer, a persistence layer for progress/bookmarks/notes, a search UI, and an appearance system — all by hand, before you get to your actual app logic. `pdf_reading_tracker` provides that entire stack as a single widget, or, if you need finer control, as a static API you can call directly:

- **One widget, full feature set** — `PdfReadingTrackerViewer` ships reading, progress, bookmarks, annotations, notes, search, and appearance out of the box.
- **No backend required** — every feature is backed by on-device SQLite; nothing depends on a network connection.
- **Composable** — every feature is also exposed through a static `PdfReadingTracker` facade, so you can build a custom UI around the same persistence layer instead of using the bundled widget.
- **Non-invasive integration** — designed to slot into an existing app's navigation and theming without requiring structural changes.

Well suited for educational apps, document libraries, e-book/e-paper readers, and any document-centric productivity tool that needs "continue where you left off" behavior without building the plumbing yourself.

## Highlights

- **Reading Progress** — automatic, persistent page tracking per document
- **Continue Reading & Recent PDFs** — dashboards backed by the same progress data
- **Bookmarks** — with optional per-bookmark notes
- **Multi-Type Annotations** — highlight, underline, strikethrough, squiggly, each with a six-color palette
- **Text-Anchored Notes** — linked to the exact selected text, independent of bookmarks
- **In-Document Search** — match navigation and result highlighting
- **Immersive Reading Mode** — distraction-free, auto-hiding chrome
- **Appearance Control** — Light / Dark / Follow-System, with an in-reader selector
- **PDF Import, Merge & Split** — manage a personal PDF library on-device
- **SQLite Persistence** — offline-first, migration-based schema

---

## Table of Contents

- [Why pdf_reading_tracker?](#why-pdf_reading_tracker)
- [Highlights](#highlights)
- [Features](#features)
- [Platform Support](#platform-support)
- [Installation](#installation)
- [Import](#import)
- [Quick Start](#quick-start)
- [Widget Configuration](#widget-configuration)
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Storage](#storage)
- [Offline Support](#offline-support)
- [Performance](#performance)
- [Example App](#example-app)
- [FAQ](#faq)
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

Add the package with:

```bash
flutter pub add pdf_reading_tracker
```

Or add it manually to `pubspec.yaml`:

```yaml
dependencies:
  pdf_reading_tracker: ^4.0.2
```

Then fetch dependencies:

```bash
flutter pub get
```

## Import

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

`pdfId` is the stable key the package uses to persist and look up progress, bookmarks, annotations, and notes for a given document. It should be unique and unchanging for the same logical document — reusing a `pdfId` across different files, or changing it for the same file, will break continuity of the stored data.

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

Beyond the widget, a static `PdfReadingTracker` facade exposes every capability programmatically — useful for dashboards, background sync, or building your own reader UI on top of the same persistence layer.

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

Search is built directly into `PdfReadingTrackerViewer` via `enableSearch: true` — it provides in-document text search with match navigation and result highlighting, with no additional wiring required.

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

```
┌─────────────────────────────────────────────┐
│              PdfReadingTrackerViewer         │
│   (widget: rendering, gestures, chrome)      │
└───────────────┬───────────────────────────────┘
                │
     ┌──────────┼───────────────┬───────────────┐
     ▼          ▼                ▼               ▼
 Progress   Bookmarks/       Appearance /    PDF Ops
 Service    Annotations/     Reading         (Import,
            Notes Services   Settings        Merge, Split)
     │          │                │               │
     └──────────┴───────┬────────┘               │
                         ▼                        ▼
                  SQLite (persistence)     Syncfusion PDF
                                            processing engine
```

- **Rendering** — Syncfusion PDF Viewer handles on-device rendering and text selection.
- **PDF processing** — the Syncfusion PDF processing engine powers merge/split operations.
- **Persistence** — a dedicated SQLite layer, offline-first by design.
- **Service-based separation** — reading progress, bookmarks, annotations, and notes are each handled by their own service, avoiding a monolithic data layer.
- **Appearance/immersive layer** — a lightweight, listenable-based theming and visibility controller that never forces a rebuild of the PDF surface itself.

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

## FAQ

**Do I need a backend or API key to use this package?**
No. All persistence is local, on-device SQLite. There is no network dependency for any feature.

**Can I use my own PDF viewer UI instead of `PdfReadingTrackerViewer`?**
Yes. Every capability — progress, bookmarks, highlights, notes, import, merge, split — is also available through the static `PdfReadingTracker` facade and standalone services, so you can build a custom UI on top of the same persistence layer.

**What happens if I change a document's `pdfId`?**
Progress, bookmarks, annotations, and notes are keyed by `pdfId`. Changing it for an existing document will disconnect it from its previously stored data.

**Can I provide both `assetPath` and `filePath`?**
No — exactly one must be provided per `PdfReadingTrackerViewer` instance.

**Does the package support cloud sync?**
Not currently. All data is stored locally via SQLite; see [Roadmap](#roadmap) for planned work.

---

## Roadmap

- [ ] Further refinement of dominant/exact page detection accuracy
- [ ] Expanded search customization options
- [ ] Additional annotation types

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