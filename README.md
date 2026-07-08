# pdf_reading_tracker

[![pub package](https://img.shields.io/pub/v/pdf_reading_tracker.svg)](https://pub.dev/packages/pdf_reading_tracker)
[![pub points](https://img.shields.io/pub/points/pdf_reading_tracker)](https://pub.dev/packages/pdf_reading_tracker/score)
[![likes](https://img.shields.io/pub/likes/pdf_reading_tracker)](https://pub.dev/packages/pdf_reading_tracker/score)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios-blue.svg)](#platform-support)

A complete, drop-in Flutter PDF reader — progress tracking, bookmarks, multi-type annotations, text-anchored notes, in-document search, appearance theming, and offline-first SQLite persistence, built on top of Syncfusion PDF Viewer.

## Why pdf_reading_tracker?

Building a real PDF reading experience usually means wiring together a viewer, a persistence layer for progress/bookmarks/notes, a search UI, and an appearance system — all before you get to your actual app logic. `pdf_reading_tracker` provides that entire stack as a single widget, or, if you need finer control, as a static API and toolbar building blocks you can compose into your own UI.

- **One widget, full feature set** — `PdfReadingTrackerViewer` ships reading, progress, bookmarks, annotations, notes, search, and appearance out of the box.
- **No backend required** — every feature is backed by on-device SQLite; nothing depends on a network connection.
- **Composable** — every feature is also exposed through a static `PdfReadingTracker` facade and a `readerActions` API, so you can build a fully custom UI (including your own app bar and toolbar) around the same persistence layer instead of using the bundled chrome.
- **Non-invasive integration** — designed to slot into an existing app's navigation, app bar, and theming without requiring structural changes to your app.

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
- **Host Toolbar Integration** — drive every reader action from your own app bar or toolbar via `readerActions` and `readerListenable`
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
- [Integrating with Your Own App Bar](#integrating-with-your-own-app-bar)
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
| **Host Integration** | External app bar support, `showAppBar: false`, `readerActions`, `readerListenable`, prebuilt toolbar buttons |
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

### Host Toolbar Integration
- `showAppBar: false` to fully hand app bar duties to your host app
- `readerActions` — a typed API for triggering reader actions (bookmark, note, search, appearance, reading settings, jump-to-page) from outside the widget
- `readerListenable` — a `Listenable` for reflecting reader state (e.g. current page, bookmark status) in your own UI
- Prebuilt toolbar buttons — `BookmarkButton`, `NotesButton`, `HighlightsButton`, `SearchButton`, `AppearanceButton`, `ReadingSettingsButton`, `JumpToPageButton` — for dropping straight into a custom `PdfReaderToolbar` or your existing app bar

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
  pdf_reading_tracker: ^4.1.0
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

## Integrating with Your Own App Bar

New in 4.1.0: `PdfReadingTrackerViewer` can hand off all of its chrome to your host app instead of rendering its own app bar. This is the recommended path if your app already has a navigation shell and you want reader controls (bookmark, search, appearance, jump-to-page, etc.) to live in your own toolbar.

```dart
class MyReaderScreen extends StatefulWidget {
  const MyReaderScreen({super.key});

  @override
  State<MyReaderScreen> createState() => _MyReaderScreenState();
}

class _MyReaderScreenState extends State<MyReaderScreen> {
  final _viewerKey = GlobalKey<PdfReadingTrackerViewerState>();

  PdfReaderActions get _actions => _viewerKey.currentState!.readerActions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Document'),
        actions: [
          BookmarkButton(actions: _actions),
          SearchButton(actions: _actions),
          NotesButton(actions: _actions),
          HighlightsButton(actions: _actions),
          AppearanceButton(actions: _actions),
          ReadingSettingsButton(actions: _actions),
          JumpToPageButton(actions: _actions),
        ],
      ),
      body: PdfReadingTrackerViewer(
        key: _viewerKey,
        pdfId: 'clean_architecture',
        pdfTitle: 'Clean Architecture',
        assetPath: 'assets/pdfs/clean_architecture.pdf',
        showAppBar: false,
      ),
    );
  }
}
```

Or use the bundled `PdfReaderToolbar` to render the same buttons as a ready-made bottom or app bar toolbar without wiring each button individually:

```dart
PdfReaderToolbar(
  actions: _actions,
)
```

For UI that needs to react to reader state directly (current page, bookmark status, search open/closed, etc.), listen to `readerListenable`:

```dart
AnimatedBuilder(
  animation: _viewerKey.currentState!.readerListenable,
  builder: (context, _) {
    final isBookmarked = _actions.isCurrentPageBookmarked;
    return Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border);
  },
)
```

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
| `showAppBar` | `bool` | `true` | Show the built-in app bar, or set to `false` to drive the reader from your own app bar via `readerActions` |
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

### Reader Actions (host toolbar integration)

```dart
final actions = viewerKey.currentState!.readerActions;

actions.toggleBookmark();
actions.openSearch();
actions.jumpToPage(42);
actions.setAppearanceMode(AppearanceMode.dark);
```

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
     ┌──────────┼───────────────┬───────────────┬───────────────┐
     ▼          ▼                ▼               ▼               ▼
 Progress   Bookmarks/       Appearance /    PDF Ops         Host Toolbar
 Service    Annotations/     Reading         (Import,        (readerActions,
            Notes Services   Settings        Merge, Split)   readerListenable)
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
- **Host integration layer** — `readerActions` and `readerListenable` expose the same internal state and commands the built-in chrome uses, so a host-supplied app bar has the same capabilities as the default one.

---

## Storage

- Lightweight, migration-based SQLite schema
- Efficient annotation and note storage (multi-rect selections stored per annotation/note)
- Automatic cleanup of temporary files created during import, merge, or split operations
- No cloud sync or network dependency — everything lives on-device

---

## Offline Support

`pdf_reading_tracker` is fully offline-first: reading progress, bookmarks, highlights, and notes are all persisted locally via SQLite, and no feature in the package — including the host toolbar integration — requires a network connection at any point.

---

## Performance

- Background isolate-based page-geometry reads to avoid UI jank on large documents
- Binary-search page lookup over precomputed normalized page offsets for fast, accurate page detection
- Debounced progress persistence to minimize redundant database writes
- Appearance and reading-settings changes are isolated via scoped `ListenableBuilder`s so the PDF surface itself never rebuilds during a theme transition

---

## Example App

The `example/` app demonstrates the full feature set end-to-end: PDF reading, progress tracking, continue-reading, recent PDFs, bookmarks, notes, highlights, appearance switching, immersive reading mode, host app bar integration, PDF import, merge, and split.

---

## FAQ

**Do I need a backend or API key to use this package?**
No. All persistence is local, on-device SQLite. There is no network dependency for any feature.

**Can I use my own PDF viewer UI instead of `PdfReadingTrackerViewer`?**
Yes. Every capability — progress, bookmarks, highlights, notes, import, merge, split — is also available through the static `PdfReadingTracker` facade and standalone services, so you can build a fully custom UI on top of the same persistence layer.

**Can I use my own app bar or toolbar instead of the built-in one?**
Yes. Set `showAppBar: false` and drive the reader through `readerActions`, either by wiring the prebuilt toolbar buttons (`BookmarkButton`, `SearchButton`, `NotesButton`, `HighlightsButton`, `AppearanceButton`, `ReadingSettingsButton`, `JumpToPageButton`) into your own app bar, or by using the bundled `PdfReaderToolbar`.

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
- [ ] Optional cloud sync backend
- [ ] Native swipe-threshold page snapping

---

## Known Limitations

- Reading progress relies on Syncfusion page-change events combined with visible-area detection; exact dominant-page accuracy is still being refined.
- Native swipe-threshold page snapping is not yet implemented (pending a future Syncfusion viewer upgrade).

---

## Contributing

Contributions are welcome — bug reports, feature requests, and pull requests all help.

1. Open an issue first for any significant change, so the approach can be discussed before you invest time in a PR.
2. Fork the repository and create a feature branch off `main`.
3. Keep changes focused; unrelated formatting or refactor changes make PRs harder to review.
4. Run `flutter analyze` and the existing test suite before submitting.
5. Submit a pull request against `main` with a clear description of the change and its motivation.

- **Issues & feature requests:** [GitHub Issues](https://github.com/ArunKumar73177/pdf_reading_tracker/issues)
- **Pull requests:** [github.com/ArunKumar73177/pdf_reading_tracker](https://github.com/ArunKumar73177/pdf_reading_tracker)

---

## License

MIT License