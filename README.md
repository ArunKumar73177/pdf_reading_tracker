# PDF Reading Tracker

A lightweight Flutter package for tracking PDF reading progress and bookmarks using SQLite.

## Features

* Save reading progress
* Resume reading from the last page
* Add bookmarks
* Retrieve bookmarks
* Delete bookmarks
* SQLite-based local persistence
* Lightweight and easy to integrate

## Installation

```yaml
dependencies:
  pdf_reading_tracker: ^1.0.0
```

## Usage

```dart
import 'package:pdf_reading_tracker/pdf_reading_tracker.dart';
```

### Save Progress

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

### Get Progress

```dart
final progress =
    await PdfReadingTracker.getProgress('pdf_001');
```

### Add Bookmark

```dart
await PdfReadingTracker.addBookmark(
  Bookmark.create(
    pdfId: 'pdf_001',
    page: 20,
    note: 'Important Topic',
  ),
);
```

### Get Bookmarks

```dart
final bookmarks =
    await PdfReadingTracker.getBookmarks('pdf_001');
```

## Platform Support

* Android
* iOS
* Windows
* macOS
* Linux

## License

MIT License

