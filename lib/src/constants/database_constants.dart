/// Central registry for all SQLite table names and column identifiers.
abstract final class DatabaseConstants {
  DatabaseConstants._();

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks        = 'bookmarks';
  static const String tableHighlights       = 'highlights';

  // ---------------------------------------------------------------------------
  // Shared columns
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
  // highlights columns
  // ---------------------------------------------------------------------------

  static const String columnSelectedText = 'selected_text';

  /// Pipe-separated list of "left,top,right,bottom" rect strings.
  /// Replaces the old single-rect `bounds` column.
  static const String columnRectList   = 'rect_list';
  static const String columnColorValue = 'color_value';

  // ---------------------------------------------------------------------------
  // DDL
  // ---------------------------------------------------------------------------

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

  /// highlights table — supports multiple rects per row via [columnRectList].
  static const String createHighlightsTable = '''
    CREATE TABLE IF NOT EXISTS $tableHighlights (
      $columnId           INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId        TEXT    NOT NULL,
      $columnPage         INTEGER NOT NULL,
      $columnSelectedText TEXT    NOT NULL,
      $columnRectList     TEXT    NOT NULL,
      $columnColorValue   INTEGER NOT NULL,
      $columnCreatedAt    TEXT    NOT NULL,
      $columnNote         TEXT,
      FOREIGN KEY ($columnPdfId)
        REFERENCES $tableReadingProgress ($columnPdfId)
        ON DELETE CASCADE
    )
  ''';

  static const String createHighlightsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_highlights_pdf_page
    ON $tableHighlights ($columnPdfId, $columnPage)
  ''';
}