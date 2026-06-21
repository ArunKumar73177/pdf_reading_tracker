import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';

/// Opens and manages the application SQLite database.
///
/// ### Schema version history
/// | Version | Change                                                          |
/// |---------|-----------------------------------------------------------------|
/// | 1       | reading_progress + bookmarks                                    |
/// | 2       | reading_progress: added file_path                               |
/// | 3       | reading_progress: added title                                   |
/// | 4       | highlights table (old schema with single `bounds` column)       |
/// | 5       | highlights: replaced `bounds` with `rect_list` (multi-rect)     |
/// | 6       | highlights: added `annotation_type` TEXT DEFAULT 'highlight'    |
/// | 7       | notes table — standalone, page-scoped notes                     |
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _kDbName    = 'pdf_reading_tracker.db';
  static const int    _kDbVersion = 7;

  Database? _database;

  Future<Database> get database async {
    _database ??= await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _kDbName);
    return openDatabase(
      path,
      version:     _kDbVersion,
      onCreate:    _onCreate,
      onUpgrade:   _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

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
      // v3 → v4: old highlights table with single `bounds` column.
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
      // v4 → v5: old screen-space rects cannot be converted to PDF page-space
      // without the document, so the table is rebuilt. Old highlights lost —
      // this was documented in the v5 release.
      await db.execute(
          'DROP TABLE IF EXISTS ${DatabaseConstants.tableHighlights}');
      await db.execute(DatabaseConstants.createHighlightsTable);
      await db.execute(DatabaseConstants.createHighlightsIndex);
    }

    if (oldVersion < 6) {
      // v5 → v6: non-destructive column addition.
      // Existing highlight rows default to annotation_type = 'highlight',
      // preserving all previously saved highlights without any data loss.
      await db.execute(DatabaseConstants.migrateHighlightsV5ToV6);
    }

    if (oldVersion < 7) {
      // v6 → v7: new standalone notes table. Purely additive — does not
      // touch highlights, bookmarks, or reading_progress in any way.
      await db.execute(DatabaseConstants.createNotesTable);
      await db.execute(DatabaseConstants.createNotesIndex);
    }

    debugPrint('[DatabaseHelper] Upgrade complete → v$newVersion');
  }
}