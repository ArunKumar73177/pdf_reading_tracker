# pdf_reading_tracker

A complete Flutter PDF reader and PDF operations package.

Render PDFs, track reading progress, manage bookmarks, merge PDFs, split PDFs, and persist everything locally using SQLite.

Built on top of:

* ALH PDF View (Rendering)
* SQLite (Persistence)
* Syncfusion PDF (PDF Operations)

---

## Features

### PDF Reading

* PDF rendering via ALH PDF View
* Horizontal page navigation
* Double-tap zoom support
* Multi-PDF support
* Continue reading from last page

### Reading Progress

* Automatic progress tracking
* Resume from last opened page
* Progress percentage calculation
* Offline persistence using SQLite

### Bookmarks

* Add bookmarks
* Remove bookmarks
* Bookmark notes
* Persistent bookmark storage

### PDF Operations

* Merge multiple PDFs
* Split PDFs into smaller files
* Isolate-based PDF processing
* Typed exception handling

### Architecture

* Flutter package architecture
* SQLite-backed storage
* Offline-first design
* Clean service-based implementation

---

## Platform Support

| Android | iOS |
| ------- | --- |
| ✅       | ✅   |

---

## Installation

```yaml
dependencies:
  pdf_reading_tracker: ^2.0.1
```

---

## Android Setup

The package depends on ALH PDF View which uses JitPack internally.

Add JitPack to your Android repositories.

### build.gradle

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }
}
```

### settings.gradle.kts

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(
        RepositoriesMode.FAIL_ON_PROJECT_REPOS
    )

    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}
```

---

## Import

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

---

# PDF Reader Widget

The easiest way to use the package.

```dart
PdfReadingTrackerViewer(
  pdfId: 'clean_architecture_v1',
  pdfTitle: 'Clean Architecture',
  assetPath: 'assets/docs/clean_architecture.pdf',
)
```

---

## Advanced Reader Configuration

```dart
PdfReadingTrackerViewer(
  pdfId: 'clean_architecture_v1',
  pdfTitle: 'Clean Architecture',
  assetPath: 'assets/docs/clean_architecture.pdf',

  showAppBar: true,
  showBottomBar: true,
  showBookmarkFab: true,

  swipeHorizontal: true,
  enableDoubleTap: true,

  onPageChanged: (page, totalPages) {
    print('Current page: $page');
  },

  theme: PdfViewerTheme(
    appBarBackgroundColor: Colors.indigo,
    appBarForegroundColor: Colors.white,
  ),
)
```

---

# Progress Tracking API

## Save Progress

```dart
await PdfReadingTracker.saveProgress(
  ReadingProgress.create(
    pdfId: 'pdf_001',
    currentPage: 25,
    totalPages: 100,
    title: 'Flutter Notes',
  ),
);
```

---

## Get Progress

```dart
final progress =
    await PdfReadingTracker.getProgress('pdf_001');
```

---

## Get All Progress

```dart
final allProgress =
    await PdfReadingTracker.getAllProgress();
```

---

# Bookmark API

## Add Bookmark

```dart
await PdfReadingTracker.addBookmark(
  Bookmark.create(
    pdfId: 'pdf_001',
    page: 25,
    note: 'Important concept',
  ),
);
```

---

## Get Bookmarks

```dart
final bookmarks =
    await PdfReadingTracker.getBookmarks('pdf_001');
```

---

## Remove Bookmark

```dart
await PdfReadingTracker.removeBookmark(bookmarkId);
```

---

# PDF Merge

Merge multiple PDF files into a single PDF.

```dart
final mergedPdfPath =
    await PdfMergeService.merge(
      inputPaths: [
        pdf1,
        pdf2,
        pdf3,
      ],
    );
```

Returns:

```text
/path/to/merged.pdf
```

---

# PDF Split

Split a PDF into multiple smaller PDFs.

```dart
final files =
    await PdfSplitService.split(
      pdfPath: sourcePdf,
      pagesPerFile: 25,
    );
```

Returns:

```dart
[
  part1.pdf,
  part2.pdf,
  part3.pdf,
]
```

---

# Error Handling

```dart
try {
  await PdfMergeService.merge(
    inputPaths: [pdf1, pdf2],
  );
} on PdfMergeException catch (e) {
  print(e);
}
```

```dart
try {
  await PdfSplitService.split(
    pdfPath: sourcePdf,
    pagesPerFile: 25,
  );
} on PdfSplitException catch (e) {
  print(e);
}
```

---

# Example Application

The package includes a complete example application demonstrating:

* PDF Reader
* Multiple PDFs
* Reading Progress
* Bookmark Persistence
* PDF Merge
* PDF Split

---

# Roadmap

Upcoming Features:

* Upload User PDF
* Recent PDFs
* Continue Reading Dashboard
* Jump To Page
* Text Search
* Text Highlighting
* PDF Annotation
* Extract Pages
* Delete Pages
* Rotate Pages
* Password Protected PDFs
* Thumbnail Navigation

---

# License

MIT License
