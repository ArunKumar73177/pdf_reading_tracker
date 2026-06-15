/// Centralised constants for every SQLite identifier used by
/// [pdf_reading_tracker].
///
/// Keeping all names here means a typo in a column name is a compile-time
/// error, not a silent runtime bug.
abstract final class DatabaseConstants {
  DatabaseConstants._();

  // ---------------------------------------------------------------------------
  // Database metadata
  // ---------------------------------------------------------------------------

  static const String kDatabaseName = 'pdf_reading_tracker.db';

  /// Schema version history:
  /// | v | Change                                               |
  /// |---|------------------------------------------------------|
  /// | 1 | Initial schema (reading_progress, bookmarks)         |
  /// | 2 | Added `title` to reading_progress                    |
  /// | 3 | (reserved / no-op bump in previous session)          |
  /// | 4 | Added `file_path` to reading_progress (Phase 1)      |
  static const int kDatabaseVersion = 4;

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks = 'bookmarks';

  // ---------------------------------------------------------------------------
  // Shared columns
  // ---------------------------------------------------------------------------

  static const String columnId = 'id';
  static const String columnPdfId = 'pdf_id';
  static const String columnCreatedAt = 'created_at';

  // ---------------------------------------------------------------------------
  // reading_progress columns
  // ---------------------------------------------------------------------------

  static const String columnCurrentPage = 'current_page';
  static const String columnTotalPages = 'total_pages';
  static const String columnProgressPct = 'progress_pct';
  static const String columnLastReadAt = 'last_read_at';
  static const String columnTitle = 'title';

  /// Absolute on-device file path for user-picked PDFs.
  ///
  /// `NULL` for asset-backed PDFs bundled with the app.
  /// Non-null for any PDF the user picked via [PdfPickerService].
  /// Used to verify the file still exists before opening and to
  /// distinguish user PDFs from asset PDFs in the UI.
  static const String columnFilePath = 'file_path';

  // ---------------------------------------------------------------------------
  // bookmarks columns
  // ---------------------------------------------------------------------------

  static const String columnPage = 'page';
  static const String columnNote = 'note';
}