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

  /// File name of the SQLite database on disk.
  static const String kDatabaseName = 'pdf_reading_tracker.db';

  /// Schema version.
  ///
  /// | Version | Change                                      |
  /// |---------|---------------------------------------------|
  /// | 1       | Initial schema (reading_progress, bookmarks)|
  /// | 2       | Added `title` column to reading_progress    |
  ///
  /// Bump this value whenever [_onUpgrade] gains a new migration step.
  static const int kDatabaseVersion = 2;

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks = 'bookmarks';

  // ---------------------------------------------------------------------------
  // Shared columns
  // ---------------------------------------------------------------------------

  /// Auto-incremented integer primary key present in every table.
  static const String columnId = 'id';

  /// Foreign / primary key linking both tables to a specific PDF document.
  static const String columnPdfId = 'pdf_id';

  /// ISO-8601 UTC timestamp stored as TEXT (SQLite has no native DATETIME).
  static const String columnCreatedAt = 'created_at';

  // ---------------------------------------------------------------------------
  // reading_progress columns
  // ---------------------------------------------------------------------------

  static const String columnCurrentPage = 'current_page';
  static const String columnTotalPages = 'total_pages';

  /// Completion percentage in [0.0, 100.0]; stored for fast querying.
  static const String columnProgressPct = 'progress_pct';

  /// ISO-8601 UTC timestamp of the last read event.
  static const String columnLastReadAt = 'last_read_at';

  /// Optional human-readable document title. Added in schema v2.
  static const String columnTitle = 'title';

  // ---------------------------------------------------------------------------
  // bookmarks columns
  // ---------------------------------------------------------------------------

  /// Zero-based page index of the bookmarked page.
  static const String columnPage = 'page';

  /// Optional user annotation for the bookmark.
  static const String columnNote = 'note';
}