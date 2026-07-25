# pdf_reading_tracker

A Flutter PDF reader widget with reading-progress tracking, bookmarks, multi-type annotations, text-anchored notes, in-document search, and offline SQLite persistence — built on Syncfusion PDF Viewer.

[![pub package](https://img.shields.io/pub/v/pdf_reading_tracker.svg)](https://pub.dev/packages/pdf_reading_tracker)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Table of Contents

- [Features](#features)
- [Why use this package](#why-use-this-package)
- [Installation](#installation)
- [Environment requirements](#environment-requirements)
- [Permissions](#permissions)
- [Quick Start](#quick-start)
- [Complete usage example](#complete-usage-example)
- [API overview](#api-overview)
- [Reading progress](#reading-progress)
- [Bookmarks](#bookmarks)
- [Highlights and annotations](#highlights-and-annotations)
- [Notes](#notes)
- [Immersive reading mode](#immersive-reading-mode)
- [Do Not Disturb (Android)](#do-not-disturb-android)
- [Host toolbar integration](#host-toolbar-integration)
- [Best practices](#best-practices)
- [Platform support](#platform-support)
- [Architecture](#architecture)
- [Storage](#storage)
- [Performance](#performance)
- [Known limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

## Features

- Reading progress tracking with continue-reading and recently-read data
- Bookmarks with optional per-bookmark notes
- Multi-type annotations (highlight, underline, strikethrough, squiggly) with a color palette
- Text-anchored notes, independent of annotations
- In-document search with match navigation
- Light / Dark / Follow-System appearance, with an in-reader selector
- Immersive reading mode with auto-hiding chrome
- Optional Do Not Disturb while reading (Android)
- Host app bar / toolbar integration (`showAppBar: false`, `readerActions`, `readerListenable`)
- PDF import, merge, and split, with typed exceptions
- Offline-first SQLite persistence

## Why use this package

Building a real PDF reading experience usually means wiring together a viewer, a persistence layer, a search UI, and an appearance system before you get to your own app logic. `pdf_reading_tracker` provides that stack as a single widget, or, for more control, as a static API plus prebuilt toolbar widgets you can compose into your own UI.

- **One widget, full feature set** — reading, progress, bookmarks, annotations, notes, search, and appearance out of the box.
- **No backend required** — every feature is backed by on-device SQLite.
- **Composable** — a static `PdfReadingTracker` facade and `readerActions` API let you build a fully custom UI on the same persistence layer.
- **Non-invasive** — slots into an existing navigation shell and theme without structural changes.

## Installation

```bash
flutter pub add pdf_reading_tracker
```

Or add manually:

```yaml
dependencies:
  pdf_reading_tracker: ^5.0.0
```

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

## Environment requirements

- Dart SDK `>=3.3.0 <4.0.0`
- Flutter `>=3.22.0`
- Android and iOS only (see [Platform support](#platform-support))

This package depends on `syncfusion_flutter_pdfviewer` and `syncfusion_flutter_pdf` for rendering and PDF processing and inherits their minimum platform SDK requirements.

## Permissions

- **File Picker** — used for importing PDFs from device storage; it manages its own platform-level access.
- **Do Not Disturb (Android only)** — requires the user to grant notification policy access via a dedicated Android settings screen. If not granted, the package reports the capability as unsupported and reading continues normally without DND.
- **iOS** — no special permissions required. DND has no iOS equivalent and is reported as unsupported there.

## Quick Start

```dart
PdfReadingTrackerViewer(
  pdfId: 'clean_architecture',
  pdfTitle: 'Clean Architecture',
  assetPath: 'assets/pdfs/clean_architecture.pdf',
)
```

Reading progress, bookmarks, highlights, and notes are automatically tracked and persisted for this `pdfId`.

Reading a user-picked or downloaded file instead of a bundled asset:

```dart
PdfReadingTrackerViewer(
  pdfId: 'user_document_42',
  pdfTitle: 'My Document',
  filePath: '/data/user/0/.../user_pdfs/document_42.pdf',
)
```

> Provide exactly one of `assetPath` or `filePath`.

`pdfId` is the stable key used to persist progress, bookmarks, annotations, and notes. Keep it unique and unchanging per logical document.

## Complete usage example

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

  onPageChanged: (page, total) => debugPrint('Page $page of $total'),
)
```

### Widget configuration

| Parameter | Type | Default | Description |
|---|---|---|---|
| `pdfId` | `String` | required | Stable, unique identifier used as the persistence key |
| `pdfTitle` | `String` | required | Display title shown in the app bar |
| `assetPath` | `String?` | — | Bundled asset PDF. Mutually exclusive with `filePath` |
| `filePath` | `String?` | — | PDF on device storage. Mutually exclusive with `assetPath` |
| `onPageChanged` | `void Function(int page, int total)?` | — | Called whenever the current page changes |
| `theme` | `PdfViewerTheme?` | — | Optional host-app color overrides for the app bar |
| `swipeHorizontal` | `bool` | `false` | Horizontal (paged) vs. vertical (continuous) navigation |
| `enableDoubleTap` | `bool` | `true` | Enable double-tap-to-zoom |
| `showAppBar` | `bool` | `true` | Show the built-in app bar, or `false` to drive the reader from your own via `readerActions` |
| `showBottomBar` | `bool` | `true` | Show/hide the bottom progress overlay |
| `showBookmarkFab` | `bool` | `true` | Show/hide the floating bookmark/note buttons |
| `enableSearch` | `bool` | `true` | Enable in-document text search |
| `enableHighlight` | `bool` | `true` | Enable annotation creation via text selection |
| `showAppearanceToggle` | `bool` | `true` | Show the Light/Dark/System option |
| `initialAppearanceMode` | `AppearanceMode` | `AppearanceMode.system` | Starting appearance mode |
| `onAppearanceModeChanged` | `void Function(AppearanceMode mode)?` | — | Called when appearance mode changes |
| `initialReadingSettings` | `ReadingSettings?` | — | Starting immersive-mode / reading-comfort preferences |
| `showReadingSettingsToggle` | `bool` | `true` | Show the reading-settings option (immersive mode, DND) |
| `onReadingSettingsChanged` | `void Function(ReadingSettings settings)?` | — | Called when reading settings change |

## API overview

A static `PdfReadingTracker` facade exposes every capability programmatically, useful for dashboards or a fully custom reader UI:

- **Progress** — save, get, get-all, recently-read, delete, clear
- **Bookmarks** — add, get, remove, update note, clear
- **Highlights** — add, get, remove, clear
- **Notes** — add, get (all / by page), update, remove, clear
- **PDF operations** — `PdfPickerService`, `PdfMergeService`, `PdfSplitService`

Each area has a typed exception (e.g. `BookmarkServiceException`, `NoteServiceException`, `PdfMergeException`) for precise error handling.

## Reading progress

```dart
await PdfReadingTracker.saveProgress(
  ReadingProgress.create(
    pdfId: 'flutter_notes',
    currentPage: 25,
    totalPages: 100,
    title: 'Flutter Notes',
  ),
);

final progress = await PdfReadingTracker.getProgress('flutter_notes');
final recent = await PdfReadingTracker.getRecentlyRead();
```

`PdfReadingTrackerViewer` tracks and persists progress automatically — use the facade above for your own dashboards or Continue Reading screens.

## Bookmarks

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

Within the built-in reader, bookmarks are added from the app bar or FAB and can carry an optional note.

## Highlights and annotations

Highlights are created interactively: selecting text surfaces an inline action bar to commit it as a highlight, underline, strikethrough, or squiggly annotation with a chosen color.

```dart
final highlights = await PdfReadingTracker.getHighlights('flutter_notes');
```

## Notes

Notes are text-anchored — linked to the exact selection the user made, not just a page number.

```dart
final notes = await PdfReadingTracker.getNotes('flutter_notes');
final pageNotes = await PdfReadingTracker.getNotesForPage('flutter_notes', 12);
```

`PdfReadingTracker.addNote` accepts a `Note` together with the captured `selectedText` and `rectList`, for building a custom note-creation flow.

## Immersive reading mode

Immersive mode hides the app bar, bottom bar, and FAB after inactivity, restoring them on tap. It's controlled through `ReadingSettings`:

```dart
PdfReadingTrackerViewer(
  pdfId: 'flutter_notes',
  pdfTitle: 'Flutter Notes',
  assetPath: 'assets/pdfs/flutter_notes.pdf',
  showReadingSettingsToggle: true,
  onReadingSettingsChanged: (settings) {
    debugPrint('Immersive mode: ${settings.immersiveModeEnabled}');
  },
)
```

A host app driving its own app bar (`showAppBar: false`) can stay in sync with immersive chrome using `ImmersiveChromeVisibility`, or by reading `immersiveChromeVisible` off `PdfReadingTrackerViewerState`.

## Do Not Disturb (Android)

Reading Settings can enable Android's Do Not Disturb for a reading session:

- Requires the user to grant notification policy access via a dedicated settings screen — there is no standard runtime prompt for this.
- Without that permission, or on iOS, the package reports the capability as unsupported rather than failing; reading continues normally without DND.
- Surfaced through the Reading Settings sheet (app bar overflow menu, or `ReadingSettingsButton` in a host toolbar) — no manual wiring needed in most integrations.

## Host toolbar integration

Hand off all chrome to your own app bar using `showAppBar: false` with `readerActions`:

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

Or render the same set as a ready-made toolbar:

```dart
PdfReaderToolbar(actions: _actions)
```

React to reader state (current page, bookmark status, search visibility) with `readerListenable`:

```dart
AnimatedBuilder(
  animation: _viewerKey.currentState!.readerListenable,
  builder: (context, _) {
    final isBookmarked = _actions.isCurrentPageBookmarked;
    return Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border);
  },
)
```

## Best practices

- Treat `pdfId` as permanent — generate it once per document and never reuse it for a different file.
- Attach a `GlobalKey<PdfReadingTrackerViewerState>` only when using `readerActions` (i.e. `showAppBar: false`).
- Prefer the prebuilt toolbar buttons / `PdfReaderToolbar` over reimplementing reader actions — they stay in sync with internal state automatically.
- Give `PdfReadingTrackerViewer` a stable `key` when it's rebuilt inside a larger widget tree, to avoid losing in-memory reader state.

## Platform support

| Android | iOS |
|:---:|:---:|
| ✅ | ✅ |

Do Not Disturb is Android-only; all other features behave identically on both platforms.

## Architecture

```text
┌─────────────────────────────────────────────┐
│              PdfReadingTrackerViewer         │
│   (widget: rendering, gestures, chrome)      │
└───────────────┬───────────────────────────────┘
                │
     ┌──────────┼───────────────┬───────────────┬───────────────┐
     ▼          ▼                ▼               ▼               ▼
 Progress   Bookmarks/       Appearance /    PDF Ops         Host Toolbar
 Service    Annotations/     Reading         (Import,        (readerActions,
            Notes Services   Settings/DND    Merge, Split)   readerListenable)
     │          │                │               │
     └──────────┴───────┬────────┘               │
                         ▼                        ▼
                  SQLite (persistence)     Syncfusion PDF
                                            processing engine
```

Progress, bookmarks, annotations, and notes are each handled by their own service rather than a single monolithic data layer. `readerActions` and `readerListenable` expose the same state and commands the built-in chrome uses, so a host-supplied app bar has equivalent capability to the default one.

## Storage

- Lightweight, migration-based SQLite schema
- Multi-rect selections stored per annotation/note
- Automatic cleanup of temporary files from import, merge, or split
- No cloud sync or network dependency — all data lives on-device

## Performance

- Offline-first: no network round-trips for reading, progress, or annotation data
- Appearance and immersive-mode transitions are isolated from the PDF rendering surface, so switching themes or toggling chrome visibility doesn't reconstruct the viewer
- Progress writes are debounced and guarded against overlapping calls during rapid page changes

## Known limitations

- Dominant-page detection during continuous scroll relies on viewport-center heuristics; accuracy in edge cases (e.g. unusually tall/short pages) is still being refined.
- Do Not Disturb is Android-only and requires user-granted notification policy access.
- Native swipe-threshold page snapping is not yet implemented.
- No cloud sync — all persistence is local SQLite.
- Desktop and web targets are not supported.

## Roadmap

- Improved dominant-page detection accuracy
- Additional annotation types
- Optional cloud sync backend

## Contributing

Contributions are welcome.

1. Open an issue first for significant changes.
2. Fork the repository and branch off `main`.
3. Run `flutter analyze` and the test suite before submitting.
4. Open a pull request with a clear description of the change.

- [Issues](https://github.com/ArunKumar73177/pdf_reading_tracker/issues)
- [Pull requests](https://github.com/ArunKumar73177/pdf_reading_tracker)

## License

MIT License