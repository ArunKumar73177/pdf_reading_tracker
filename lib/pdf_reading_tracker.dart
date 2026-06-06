
// Public model exports — consumers need these to construct and inspect values.
export 'src/models/bookmark.dart' show Bookmark;
export 'src/models/reading_progress.dart' show ReadingProgress;

// Service exceptions are exported so callers can catch them by type without
// importing internal paths directly.
export 'src/services/bookmark_service.dart' show BookmarkServiceException;
export 'src/services/progress_service.dart' show ProgressServiceException;

import 'src/models/bookmark.dart';
import 'src/models/reading_progress.dart';
import 'src/services/bookmark_service.dart';
import 'src/services/progress_service.dart';

/// Top-level facade for the `pdf_reading_tracker` package.
///
/// All methods are static so consumers never manage an instance themselves.
/// Internal service singletons are hidden; the only public surface is this
/// class plus the exported model types.
///
/// ### Example
/// ```dart
/// // Save or update progress
/// final id = await PdfReadingTracker.saveProgress(
///   ReadingProgress.create(pdfId: 'doc_1', currentPage: 4, totalPages: 20),
/// );
///
/// // Add a bookmark
/// await PdfReadingTracker.addBookmark(
///   Bookmark.create(pdfId: 'doc_1', page: 4, note: 'Key insight'),
/// );
///
/// // Retrieve
/// final progress  = await PdfReadingTracker.getProgress('doc_1');
/// final bookmarks = await PdfReadingTracker.getBookmarks('doc_1');
/// ```
///
/// All methods propagate [ProgressServiceException] or [BookmarkServiceException]
/// on database failures — wrap calls in try/catch where appropriate.
abstract final class PdfReadingTracker {
  // Prevent instantiation and subclassing.
  PdfReadingTracker._();

  // ---------------------------------------------------------------------------
  // Progress API
  // ---------------------------------------------------------------------------

  /// Inserts or replaces the reading progress for a document.
  ///
  /// Returns the SQLite row id of the inserted / replaced record.
  /// Throws [ProgressServiceException] on failure.
  static Future<int> saveProgress(ReadingProgress progress) =>
      ProgressService.instance.saveProgress(progress);

  /// Returns the [ReadingProgress] for [pdfId], or `null` if none exists.
  ///
  /// Throws [ProgressServiceException] on failure.
  static Future<ReadingProgress?> getProgress(String pdfId) =>
      ProgressService.instance.getProgress(pdfId);

  /// Returns every [ReadingProgress] record, most-recently-read first.
  ///
  /// Returns an empty list when no records exist.
  /// Throws [ProgressServiceException] on failure.
  static Future<List<ReadingProgress>> getAllProgress() =>
      ProgressService.instance.getAllProgress();

  /// Deletes the progress record for [pdfId] and its associated bookmarks.
  ///
  /// Returns `true` if a record was deleted, `false` if none was found.
  /// Throws [ProgressServiceException] on failure.
  static Future<bool> deleteProgress(String pdfId) =>
      ProgressService.instance.deleteProgress(pdfId);

  /// Deletes **all** progress records and their associated bookmarks.
  ///
  /// This is destructive and unrecoverable — use only in explicit
  /// "clear all data" flows or test teardown.
  /// Throws [ProgressServiceException] on failure.
  static Future<void> clearAllProgress() =>
      ProgressService.instance.clearAllProgress();

  // ---------------------------------------------------------------------------
  // Bookmark API
  // ---------------------------------------------------------------------------

  /// Inserts a new [Bookmark] and returns its auto-incremented row id.
  ///
  /// Throws [BookmarkServiceException] on failure.
  static Future<int> addBookmark(Bookmark bookmark) =>
      BookmarkService.instance.addBookmark(bookmark);

  /// Returns all bookmarks for [pdfId] ordered by page number ascending.
  ///
  /// Returns an empty list when no bookmarks exist.
  /// Throws [BookmarkServiceException] on failure.
  static Future<List<Bookmark>> getBookmarks(String pdfId) =>
      BookmarkService.instance.getBookmarks(pdfId);

  /// Deletes the bookmark with the given [id].
  ///
  /// Returns `true` if a record was deleted, `false` if none was found.
  /// Throws [BookmarkServiceException] on failure.
  static Future<bool> removeBookmark(int id) =>
      BookmarkService.instance.removeBookmark(id);

  /// Deletes all bookmarks belonging to [pdfId].
  ///
  /// Throws [BookmarkServiceException] on failure.
  static Future<void> clearBookmarks(String pdfId) =>
      BookmarkService.instance.clearBookmarks(pdfId);

  /// Deletes **all** bookmarks across every document.
  ///
  /// This is destructive and unrecoverable — use only in explicit
  /// "clear all data" flows or test teardown.
  /// Throws [BookmarkServiceException] on failure.
  static Future<void> clearAllBookmarks() =>
      BookmarkService.instance.clearAllBookmarks();
}
