// ── Models ────────────────────────────────────────────────────────────────────
export 'src/models/bookmark.dart' show Bookmark;
export 'src/models/reading_progress.dart' show ReadingProgress;

// ── Service exceptions ────────────────────────────────────────────────────────
export 'src/services/bookmark_service.dart' show BookmarkServiceException;
export 'src/services/progress_service.dart' show ProgressServiceException;

// ── PDF Operations (NEW) ──────────────────────────────────────────────────────
export 'src/services/pdf_operations/pdf_operation_exception.dart'
    show
    PdfOperationException,
    PdfMergeException,
    PdfMergeFileNotFoundException,
    PdfMergeCorruptFileException,
    PdfSplitException,
    PdfSplitFileNotFoundException,
    PdfSplitInvalidRangeException;

export 'src/services/pdf_operations/pdf_merge_service.dart'
    show PdfMergeService;

export 'src/services/pdf_operations/pdf_split_service.dart'
    show PdfSplitService, PageRange;

// ── Public viewer widget ──────────────────────────────────────────────────────
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
/// For the all-in-one PDF reader experience, use [PdfReadingTrackerViewer].
/// For merge/split operations, use [PdfMergeService] and [PdfSplitService]
/// directly — they are stateless and require no instance management.
abstract final class PdfReadingTracker {
  PdfReadingTracker._();

  // ── Progress API (unchanged) ───────────────────────────────────────────────
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

  // ── Bookmark API (unchanged) ───────────────────────────────────────────────
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