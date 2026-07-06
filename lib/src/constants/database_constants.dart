/// Central registry for all SQLite table names and column identifiers.
abstract final class DatabaseConstants {
  DatabaseConstants._();

  // ---------------------------------------------------------------------------
  // Table names
  // ---------------------------------------------------------------------------

  static const String tableReadingProgress = 'reading_progress';
  static const String tableBookmarks = 'bookmarks';
  static const String tableHighlights = 'highlights';
  static const String tableNotes = 'notes';

  // ---------------------------------------------------------------------------
  // Shared columns
  // ---------------------------------------------------------------------------

  static const String columnId = 'id';
  static const String columnPdfId = 'pdf_id';
  static const String columnPage = 'page';
  static const String columnNote = 'note';
  static const String columnCreatedAt = 'created_at';
  static const String columnUpdatedAt = 'updated_at';

  // ---------------------------------------------------------------------------
  // reading_progress columns
  // ---------------------------------------------------------------------------

  static const String columnCurrentPage = 'current_page';
  static const String columnTotalPages = 'total_pages';
  static const String columnProgressPct = 'progress_pct';
  static const String columnLastReadAt = 'last_read_at';
  static const String columnTitle = 'title';
  static const String columnFilePath = 'file_path';

  // ---------------------------------------------------------------------------
  // highlights columns
  // ---------------------------------------------------------------------------

  static const String columnSelectedText = 'selected_text';

  /// Pipe-separated list of "left,top,right,bottom" rect strings.
  static const String columnRectList = 'rect_list';
  static const String columnColorValue = 'color_value';

  /// Annotation type string — one of: 'highlight', 'underline',
  /// 'strikethrough', 'squiggly'.
  /// Added in schema v6. Existing rows default to 'highlight'.
  static const String columnAnnotationType = 'annotation_type';

  // ---------------------------------------------------------------------------
  // notes columns (v8 — text-anchored notes)
  // ---------------------------------------------------------------------------

  /// Note body text.
  static const String columnNoteText = 'note_text';

  /// The text the user had selected when they created this note.
  static const String columnNoteSelectedText = 'note_selected_text';

  /// Pipe-separated bounding rects of the selected text, same encoding as
  /// [columnRectList] in the highlights table.
  static const String columnNoteRectList = 'note_rect_list';

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
  // DDL — highlights v6 (unchanged)
  // ---------------------------------------------------------------------------

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
  // DDL — notes v8 (text-anchored; replaces v7 page-only notes table)
  //
  // MIGRATION STRATEGY for v7 → v8:
  //   The v7 notes table had no selectedText / rectList columns.
  //   SQLite does not support DROP COLUMN before 3.35 and Android SQLite
  //   bundles are often older, so we rebuild the table via rename + recreate.
  //   Old v7 notes are discarded (they were page-level duplicates of bookmarks
  //   with no text context, so there is nothing meaningful to migrate).
  // ---------------------------------------------------------------------------

  static const String createNotesTable = '''
    CREATE TABLE IF NOT EXISTS $tableNotes (
      $columnId               INTEGER PRIMARY KEY AUTOINCREMENT,
      $columnPdfId            TEXT    NOT NULL,
      $columnPage             INTEGER NOT NULL,
      $columnNoteText         TEXT    NOT NULL,
      $columnNoteSelectedText TEXT    NOT NULL DEFAULT '',
      $columnNoteRectList     TEXT    NOT NULL DEFAULT '',
      $columnCreatedAt        TEXT    NOT NULL,
      $columnUpdatedAt        TEXT    NOT NULL,
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
  // ---------------------------------------------------------------------------

  static const String migrateHighlightsV5ToV6 = '''
    ALTER TABLE $tableHighlights
    ADD COLUMN $columnAnnotationType TEXT NOT NULL DEFAULT 'highlight'
  ''';

  // ---------------------------------------------------------------------------
  // Migration DDL — v7 → v8  (rebuild notes table to add text-anchor columns)
  // ---------------------------------------------------------------------------

  /// Step 1: rename the old notes table out of the way.
  static const String migrateNotesV7RenameOld =
      'ALTER TABLE $tableNotes RENAME TO notes_v7_backup';

  /// Step 2: create the new notes table (issued via [createNotesTable]).

  /// Step 3: drop the backup (old page-level rows are not migrated —
  /// they had no selectedText and are indistinguishable from bookmarks).
  static const String migrateNotesV7DropBackup =
      'DROP TABLE IF EXISTS notes_v7_backup';
}
