# pdf_reading_tracker

A complete Flutter PDF reader package with built-in reading progress tracking
and bookmark management — all backed by SQLite.

Drop in one widget and get PDF rendering, automatic progress saving, page
restoration, and bookmark management out of the box.

## Features

- PDF rendering via `alh_pdf_view`
- Automatic reading progress save & restore (last page)
- Add, view, and remove bookmarks with optional notes
- SQLite-based local persistence — works fully offline
- Zero boilerplate — one widget does everything
- Low-level static API available for advanced use cases
- Lightweight and easy to integrate

## Platform Support

| Android | iOS |
|---------|-----|
| ✅      | ✅  |

## Installation

```yaml
dependencies:
  pdf_reading_tracker: ^2.0.0
```

### Android setup (required)

`pdf_reading_tracker` depends on `alh_pdf_view` which uses JitPack internally.
Add JitPack to your app's `android/build.gradle`:

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }
}
```

If your project uses the newer `settings.gradle.kts` style:

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

No other setup is required. `alh_pdf_view` is a transitive dependency —
you do **not** need to add it to your own `pubspec.yaml`.

## Usage

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

### PdfReadingTrackerViewer — recommended

The easiest way to use the package. Handles rendering, progress, and
bookmarks automatically.

```dart
PdfReadingTrackerViewer(
pdfId: 'clean_architecture_v1',  // unique stable key for this PDF
pdfTitle: 'Clean Architecture',
assetPath: 'assets/docs/clean_architecture.pdf',
)
```

> **Important:** `pdfId` is the SQLite primary key for this document.
> Never change it after first launch — doing so loses all saved progress
> and bookmarks for that document.

### Optional parameters

```dart
PdfReadingTrackerViewer(
pdfId: 'clean_architecture_v1',
pdfTitle: 'Clean Architecture',
assetPath: 'assets/docs/clean_architecture.pdf',

// Layout
showAppBar: true,         // set false when embedding in your own Scaffold
showBottomBar: true,      // progress bar at the bottom
showBookmarkFab: true,    // floating bookmark button

// PDF behaviour
swipeHorizontal: true,
enableDoubleTap: true,

// Callbacks
onPageChanged: (page, total) {
print('Now on page $page of $total');
},

// Theming
theme: PdfViewerTheme(
appBarBackgroundColor: Colors.indigo,
appBarForegroundColor: Colors.white,
),
)
```

### Embedding inside your own Scaffold

```dart
Scaffold(
appBar: AppBar(title: Text('My Reader')),
body: PdfReadingTrackerViewer(
pdfId: 'my_doc_001',
pdfTitle: 'My Document',
assetPath: 'assets/my_doc.pdf',
showAppBar: false,      // hides the built-in AppBar
showBottomBar: false,   // optional
showBookmarkFab: false, // optional
),
)
```

---

## Low-level API (advanced)

If you need direct control over progress and bookmarks without the viewer
widget, the original static API is still available and unchanged.

### Save progress

```dart
await PdfReadingTracker.saveProgress(
ReadingProgress.create(
pdfId: 'pdf_001',
currentPage: 20,
totalPages: 100,
title: 'Operating Systems',
),
);
```

### Get progress

```dart
final progress = await PdfReadingTracker.getProgress('pdf_001');
print(progress?.currentPage); // 20
```

### Get all progress records

```dart
final allProgress = await PdfReadingTracker.getAllProgress();
```

### Delete progress

```dart
await PdfReadingTracker.deleteProgress('pdf_001');
```

### Add bookmark

```dart
await PdfReadingTracker.addBookmark(
Bookmark.create(
pdfId: 'pdf_001',
page: 20,
note: 'Important topic',
),
);
```

### Get bookmarks

```dart
final bookmarks = await PdfReadingTracker.getBookmarks('pdf_001');
```

### Remove a bookmark

```dart
await PdfReadingTracker.removeBookmark(bookmarkId);
```

### Clear all bookmarks for a document

```dart
await PdfReadingTracker.clearBookmarks('pdf_001');
```

---

## Error handling

All methods throw typed exceptions on database failure.

```dart
try {
await PdfReadingTracker.addBookmark(
Bookmark.create(pdfId: 'pdf_001', page: 5),
);
} on BookmarkServiceException catch (e) {
print('Bookmark failed: ${e.message}');
}

try {
await PdfReadingTracker.saveProgress(
ReadingProgress.create(pdfId: 'pdf_001', currentPage: 5, totalPages: 100),
);
} on ProgressServiceException catch (e) {
print('Progress save failed: ${e.message}');
}
```

---

## Migration from v1.0.0

No breaking changes. All existing `PdfReadingTracker.*` calls work without
modification.

To use the new viewer widget, add JitPack to your Android Gradle config
(see [Android setup](#android-setup-required)) and bump the version:

```yaml
dependencies:
  pdf_reading_tracker: ^2.0.0
```

---

## License

MIT License