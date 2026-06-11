// ── Models ────────────────────────────────────────────────────────────────────
export 'src/models/bookmark.dart' show Bookmark;
export 'src/models/reading_progress.dart' show ReadingProgress;

// ── Service exceptions ────────────────────────────────────────────────────────
export 'src/services/bookmark_service.dart' show BookmarkServiceException;
export 'src/services/progress_service.dart' show ProgressServiceException;

// ── Public viewer widget  (NEW) ───────────────────────────────────────────────
export 'src/viewer/pdf_reading_tracker_viewer.dart'
    show PdfReadingTrackerViewer, PdfViewerTheme;

// ── Internal imports for the static facade ───────────────────────────────────
import 'src/models/bookmark.dart';
import 'src/models/reading_progress.dart';
import 'src/services/bookmark_service.dart';
import 'src/services/progress_service.dart';

/// Top-level static façade for low-level tracker operations.
///
/// Unchanged from v1 — existing callers keep working without modification.
///
/// For the all-in-one PDF reader experience, use [PdfReadingTrackerViewer]
/// instead of calling these methods manually.
abstract final class PdfReadingTracker {
  PdfReadingTracker._();

  // Progress API (unchanged)
  static Future<int> saveProgress(ReadingProgress progress) =>
      ProgressService.instance.saveProgress(progress);
  static Future<ReadingProgress?> getProgress(String pdfId) =>
      ProgressService.instance.getProgress(pdfId);
  static Future<List<ReadingProgress>> getAllProgress() =>
      ProgressService.instance.getAllProgress();
  static Future<bool> deleteProgress(String pdfId) =>
      ProgressService.instance.deleteProgress(pdfId);
  static Future<void> clearAllProgress() =>
      ProgressService.instance.clearAllProgress();

  // Bookmark API (unchanged)
  static Future<int> addBookmark(Bookmark bookmark) =>
      BookmarkService.instance.addBookmark(bookmark);
  static Future<List<Bookmark>> getBookmarks(String pdfId) =>
      BookmarkService.instance.getBookmarks(pdfId);
  static Future<bool> removeBookmark(int id) =>
      BookmarkService.instance.removeBookmark(id);
  static Future<void> clearBookmarks(String pdfId) =>
      BookmarkService.instance.clearBookmarks(pdfId);
  static Future<void> clearAllBookmarks() =>
      BookmarkService.instance.clearAllBookmarks();
}