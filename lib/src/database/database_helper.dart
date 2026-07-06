import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';

/// Opens and manages the application SQLite database.
///
/// ### Schema version history
/// | Version | Change                                                                   |
/// |---------|--------------------------------------------------------------------------|
/// | 1       | reading_progress + bookmarks                                             |
/// | 2       | reading_progress: added file_path                                        |
/// | 3       | reading_progress: added title                                            |
/// | 4       | highlights table (old schema with single `bounds` column)                |
/// | 5       | highlights: replaced `bounds` with `rect_list` (multi-rect)              |
/// | 6       | highlights: added `annotation_type` TEXT DEFAULT 'highlight'             |
/// | 7       | notes table — standalone page-scoped notes (superseded by v8)            |
/// | 8       | notes table rebuilt — added note_selected_text + note_rect_list columns  |
///           | (old page-level notes had no text context and are not migrated)         |
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _kDbName = 'pdf_reading_tracker.db';
  static const int _kDbVersion = 8;

  Database? _database;

  Future<Database> get database async {
    _database ??= await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _kDbName);
    return openDatabase(
      path,
      version: _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Configures the database connection on every open.
  ///
  /// [_onConfigure] is the correct place for connection-level PRAGMAs that
  /// must be set before any other operation — foreign key enforcement is the
  /// canonical example.
  ///
  /// WAL mode is intentionally NOT set here. sqflite on Android routes
  /// db.execute() through Android's SQLiteDatabase.execSQL(), which rejects
  /// any SQL that returns a result set. PRAGMA journal_mode=WAL returns a
  /// row ('wal'), so execSQL() throws:
  ///   "Queries can be performed using SQLiteDatabase query or
  ///    rawQuery methods only."
  /// The rawQuery() workaround exists but is fragile across sqflite versions.
  /// More importantly, WAL provides no measurable benefit here: this plugin
  /// uses a single connection, single isolate, and a 400 ms debounced write
  /// cadence — there is never concurrent read/write contention to resolve.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Fresh install — creates all tables at the current schema version.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute(DatabaseConstants.createReadingProgressTable);
    await db.execute(DatabaseConstants.createBookmarksTable);
    await db.execute(DatabaseConstants.createHighlightsTable);
    await db.execute(DatabaseConstants.createHighlightsIndex);
    await db.execute(DatabaseConstants.createNotesTable);
    await db.execute(DatabaseConstants.createNotesIndex);
    debugPrint('[DatabaseHelper] Created schema v$version');
  }

  /// Incremental upgrades — each block is independent so a user upgrading
  /// from any old version runs every applicable block in order.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[DatabaseHelper] Upgrading v$oldVersion → v$newVersion');

    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
        'ADD COLUMN ${DatabaseConstants.columnFilePath} TEXT',
      );
    }

    if (oldVersion < 3) {
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
        'ADD COLUMN ${DatabaseConstants.columnTitle} TEXT',
      );
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableHighlights} (
          ${DatabaseConstants.columnId}           INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DatabaseConstants.columnPdfId}        TEXT    NOT NULL,
          ${DatabaseConstants.columnPage}         INTEGER NOT NULL,
          ${DatabaseConstants.columnSelectedText} TEXT    NOT NULL,
          bounds                                  TEXT    NOT NULL,
          ${DatabaseConstants.columnColorValue}   INTEGER NOT NULL,
          ${DatabaseConstants.columnCreatedAt}    TEXT    NOT NULL,
          ${DatabaseConstants.columnNote}         TEXT,
          FOREIGN KEY (${DatabaseConstants.columnPdfId})
            REFERENCES ${DatabaseConstants.tableReadingProgress} (${DatabaseConstants.columnPdfId})
            ON DELETE CASCADE
        )
      ''');
      await db.execute(DatabaseConstants.createHighlightsIndex);
    }

    if (oldVersion < 5) {
      await db
          .execute('DROP TABLE IF EXISTS ${DatabaseConstants.tableHighlights}');
      await db.execute(DatabaseConstants.createHighlightsTable);
      await db.execute(DatabaseConstants.createHighlightsIndex);
    }

    if (oldVersion < 6) {
      await db.execute(DatabaseConstants.migrateHighlightsV5ToV6);
    }

    if (oldVersion < 7) {
      // v6 → v7: original page-level notes table (now superseded by v8).
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableNotes} (
          ${DatabaseConstants.columnId}        INTEGER PRIMARY KEY AUTOINCREMENT,
          ${DatabaseConstants.columnPdfId}     TEXT    NOT NULL,
          ${DatabaseConstants.columnPage}      INTEGER NOT NULL,
          ${DatabaseConstants.columnNoteText}  TEXT    NOT NULL,
          ${DatabaseConstants.columnCreatedAt} TEXT    NOT NULL,
          ${DatabaseConstants.columnUpdatedAt} TEXT    NOT NULL,
          FOREIGN KEY (${DatabaseConstants.columnPdfId})
            REFERENCES ${DatabaseConstants.tableReadingProgress} (${DatabaseConstants.columnPdfId})
            ON DELETE CASCADE
        )
      ''');
      await db.execute(DatabaseConstants.createNotesIndex);
    }

    if (oldVersion < 8) {
      // v7 → v8: rebuild notes table to add note_selected_text and
      // note_rect_list. Old page-level rows have no text context so they are
      // not migrated — they were functionally identical to bookmarks.
      //
      // We use rename + recreate because Android SQLite < 3.35 has no
      // DROP COLUMN and we need to change the schema, not just add columns
      // (the new columns are NOT NULL with meaningful defaults, but the real
      // semantic change is that notes are now text-anchored).
      await db.execute(DatabaseConstants.migrateNotesV7RenameOld);
      await db.execute(DatabaseConstants.createNotesTable);
      await db.execute(DatabaseConstants.createNotesIndex);
      await db.execute(DatabaseConstants.migrateNotesV7DropBackup);
    }

    debugPrint('[DatabaseHelper] Upgrade complete → v$newVersion');
  }
}
