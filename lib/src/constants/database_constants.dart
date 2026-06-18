/// Central registry for all SQLite table names and column identifiers.
///
/// Changing a value here is the single place needed to rename a table or
/// column across the entire package.
abstract final class DatabaseConstants {
  DatabaseConstants._();

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks        = 'bookmarks';

  /// Added in v2.4.0 — persistent text highlights.
  static const String tableHighlights = 'highlights';

  // ---------------------------------------------------------------------------
  // Shared column names (used in multiple tables)
  // ---------------------------------------------------------------------------

  static const String columnId        = 'id';
  static const String columnPdfId     = 'pdf_id';
  static const String columnPage      = 'page';
  static const String columnNote      = 'note';
  static const String columnCreatedAt = 'created_at';

  // ---------------------------------------------------------------------------
  // reading_progress columns
  // ---------------------------------------------------------------------------

  static const String columnCurrentPage = 'current_page';
  static const String columnTotalPages  = 'total_pages';
  static const String columnProgressPct = 'progress_pct';
  static const String columnLastReadAt  = 'last_read_at';
  static const String columnTitle       = 'title';
  static const String columnFilePath    = 'file_path';

  // ---------------------------------------------------------------------------
  // highlights columns (v2.4.0)
  // ---------------------------------------------------------------------------

  static const String columnSelectedText = 'selected_text';
  static const String columnBounds       = 'bounds';
  static const String columnColorValue   = 'color_value';

  // ---------------------------------------------------------------------------
  // DDL helpers
  // ---------------------------------------------------------------------------

  /// CREATE TABLE statement for [tableReadingProgress].
  static const String createReadingProgressTable = '''
    CREATE TABLE IF NOT EXISTS $tableReadingProgress (
      $columnId          INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId       TEXT    NOT NULL UNIQUE,
      $columnCurrentPage INTEGER NOT NULL DEFAULT 0,
      $columnTotalPages  INTEGER NOT NULL DEFAULT 0,
      $columnProgressPct REAL    NOT NULL DEFAULT 0.0,
      $columnLastReadAt  TEXT    NOT NULL,
      $columnCreatedAt   TEXT    NOT NULL,
      $columnTitle       TEXT,
      $columnFilePath    TEXT
    )
  ''';

  /// CREATE TABLE statement for [tableBookmarks].
  ///
  /// Uses a unique constraint on (pdf_id, page) to prevent duplicate
  /// bookmarks on the same page.
  static const String createBookmarksTable = '''
    CREATE TABLE IF NOT EXISTS $tableBookmarks (
      $columnId        INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId     TEXT    NOT NULL,
      $columnPage      INTEGER NOT NULL,
      $columnNote      TEXT,
      $columnCreatedAt TEXT    NOT NULL,
      FOREIGN KEY ($columnPdfId)
        REFERENCES $tableReadingProgress ($columnPdfId)
        ON DELETE CASCADE,
      UNIQUE ($columnPdfId, $columnPage)
    )
  ''';

  /// CREATE TABLE statement for [tableHighlights] (v2.4.0).
  ///
  /// No UNIQUE constraint on (pdf_id, page) — multiple highlights per page
  /// are allowed.
  static const String createHighlightsTable = '''
    CREATE TABLE IF NOT EXISTS $tableHighlights (
      $columnId           INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId        TEXT    NOT NULL,
      $columnPage         INTEGER NOT NULL,
      $columnSelectedText TEXT    NOT NULL,
      $columnBounds       TEXT    NOT NULL,
      $columnColorValue   INTEGER NOT NULL,
      $columnCreatedAt    TEXT    NOT NULL,
      $columnNote         TEXT,
      FOREIGN KEY ($columnPdfId)
        REFERENCES $tableReadingProgress ($columnPdfId)
        ON DELETE CASCADE
    )
  ''';

  /// Index on highlights(pdf_id, page) for fast per-page lookups.
  static const String createHighlightsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_highlights_pdf_page
    ON $tableHighlights ($columnPdfId, $columnPage)
  ''';
}