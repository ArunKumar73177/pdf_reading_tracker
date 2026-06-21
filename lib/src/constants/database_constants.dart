/// Central registry for all SQLite table names and column identifiers.
abstract final class DatabaseConstants {
  DatabaseConstants._();

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks        = 'bookmarks';
  static const String tableHighlights       = 'highlights';
  static const String tableNotes            = 'notes';

  // ---------------------------------------------------------------------------
  // Shared columns
  // ---------------------------------------------------------------------------

  static const String columnId        = 'id';
  static const String columnPdfId     = 'pdf_id';
  static const String columnPage      = 'page';
  static const String columnNote      = 'note';
  static const String columnCreatedAt = 'created_at';
  static const String columnUpdatedAt = 'updated_at';

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

  static const String columnSelectedText   = 'selected_text';

  /// Pipe-separated list of "left,top,right,bottom" rect strings.
  static const String columnRectList       = 'rect_list';
  static const String columnColorValue     = 'color_value';

  /// Annotation type string — one of: 'highlight', 'underline',
  /// 'strikethrough', 'squiggly'.
  /// Added in schema v6. Existing rows default to 'highlight'.
  static const String columnAnnotationType = 'annotation_type';

  // ---------------------------------------------------------------------------
  // notes columns
  // ---------------------------------------------------------------------------

  /// Note body text. Distinct column name from the legacy `highlights.note`
  /// column so the two concepts never collide in a shared query.
  static const String columnNoteText = 'note_text';

  // ---------------------------------------------------------------------------
  // DDL — reading_progress (unchanged)
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

  // ---------------------------------------------------------------------------
  // DDL — bookmarks (unchanged)
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // DDL — highlights v6 (adds annotation_type column)
  // ---------------------------------------------------------------------------

  /// Full highlights table DDL used on fresh installs (schema v7+).
  static const String createHighlightsTable = '''
    CREATE TABLE IF NOT EXISTS $tableHighlights (
      $columnId             INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId          TEXT    NOT NULL,
      $columnPage           INTEGER NOT NULL,
      $columnSelectedText   TEXT    NOT NULL,
      $columnRectList       TEXT    NOT NULL,
      $columnColorValue     INTEGER NOT NULL,
      $columnAnnotationType TEXT    NOT NULL DEFAULT 'highlight',
      $columnCreatedAt      TEXT    NOT NULL,
      $columnNote           TEXT,
      FOREIGN KEY ($columnPdfId)
        REFERENCES $tableReadingProgress ($columnPdfId)
        ON DELETE CASCADE
    )
  ''';

  static const String createHighlightsIndex = '''
    CREATE INDEX IF NOT EXISTS idx_highlights_pdf_page
    ON $tableHighlights ($columnPdfId, $columnPage)
  ''';

  // ---------------------------------------------------------------------------
  // DDL — notes (new in schema v7)
  // ---------------------------------------------------------------------------

  /// Standalone, page-scoped notes — independent of [tableHighlights].
  static const String createNotesTable = '''
    CREATE TABLE IF NOT EXISTS $tableNotes (
      $columnId        INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId     TEXT    NOT NULL,
      $columnPage      INTEGER NOT NULL,
      $columnNoteText  TEXT    NOT NULL,
      $columnCreatedAt TEXT    NOT NULL,
      $columnUpdatedAt TEXT    NOT NULL,
      FOREIGN KEY ($columnPdfId)
        REFERENCES $tableReadingProgress ($columnPdfId)
        ON DELETE CASCADE
    )
  ''';

  static const String createNotesIndex = '''
    CREATE INDEX IF NOT EXISTS idx_notes_pdf_page
    ON $tableNotes ($columnPdfId, $columnPage)
  ''';

  // ---------------------------------------------------------------------------
  // Migration DDL — v5 → v6
  // Adds annotation_type to an existing highlights table without dropping it.
  // Existing rows default to 'highlight', preserving all saved annotations.
  // ---------------------------------------------------------------------------

  static const String migrateHighlightsV5ToV6 = '''
    ALTER TABLE $tableHighlights
    ADD COLUMN $columnAnnotationType TEXT NOT NULL DEFAULT 'highlight'
  ''';
}