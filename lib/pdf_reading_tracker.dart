// ── Models ────────────────────────────────────────────────────────────────────
export 'src/models/bookmark.dart' show Bookmark;
export 'src/models/reading_progress.dart' show ReadingProgress;

// ── Service exceptions ────────────────────────────────────────────────────────
export 'src/services/bookmark_service.dart' show BookmarkServiceException;
export 'src/services/progress_service.dart' show ProgressServiceException;

// ── PDF picker (Phase 1) ──────────────────────────────────────────────────────
export 'src/services/pdf_picker_service.dart'
    show PdfPickerService, PickedPdf, PdfPickerException;

// ── PDF Operations ────────────────────────────────────────────────────────────
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
/// Unchanged from v2.0.x — all existing callers keep working without
/// modification.
///
/// **Phase 1 additions**
/// - [PdfPickerService.pickPdf] — pick a user PDF via the OS file picker.
/// - [ProgressService.getRecentlyRead] — recent + continue-reading data.
/// - [BookmarkService.updateNote] — edit a bookmark's note after creation.
///
/// For the all-in-one reader, use [PdfReadingTrackerViewer].
abstract final class PdfReadingTracker {
  PdfReadingTracker._();

  // ── Progress API ───────────────────────────────────────────────────────────
  static Future<int> saveProgress(ReadingProgress progress) =>
      ProgressService.instance.saveProgress(progress);
  static Future<ReadingProgress?> getProgress(String pdfId) =>
      ProgressService.instance.getProgress(pdfId);
  static Future<List<ReadingProgress>> getAllProgress() =>
      ProgressService.instance.getAllProgress();
  static Future<List<ReadingProgress>> getRecentlyRead({int limit = 20}) =>
      ProgressService.instance.getRecentlyRead(limit: limit);
  static Future<bool> deleteProgress(String pdfId) =>
      ProgressService.instance.deleteProgress(pdfId);
  static Future<void> clearAllProgress() =>
      ProgressService.instance.clearAllProgress();

  // ── Bookmark API ───────────────────────────────────────────────────────────
  static Future<int> addBookmark(Bookmark bookmark) =>
      BookmarkService.instance.addBookmark(bookmark);
  static Future<List<Bookmark>> getBookmarks(String pdfId) =>
      BookmarkService.instance.getBookmarks(pdfId);
  static Future<bool> removeBookmark(int id) =>
      BookmarkService.instance.removeBookmark(id);
  static Future<bool> updateBookmarkNote(int id, String? note) =>
      BookmarkService.instance.updateNote(id, note);
  static Future<void> clearBookmarks(String pdfId) =>
      BookmarkService.instance.clearBookmarks(pdfId);
  static Future<void> clearAllBookmarks() =>
      BookmarkService.instance.clearAllBookmarks();
}