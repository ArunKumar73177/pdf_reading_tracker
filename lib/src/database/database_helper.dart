import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../constants/database_constants.dart';

/// Opens and manages the SQLite database for the package.
///
/// ### Schema version history
/// | Version | Change                                              |
/// |---------|-----------------------------------------------------|
/// | 1       | Initial: reading_progress + bookmarks               |
/// | 2       | Added file_path to reading_progress                 |
/// | 3       | Added title to reading_progress                     |
/// | 4       | Added highlights table + idx_highlights_pdf_page    |
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _kDbName      = 'pdf_reading_tracker.db';
  static const int    _kDbVersion   = 4;

  Database? _database;

  Future<Database> get database async {
    _database ??= await _openDatabase();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // Open / create
  // ---------------------------------------------------------------------------

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _kDbName);

    return openDatabase(
      path,
      version:  _kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// Enable foreign-key enforcement on every connection.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Full schema creation from scratch.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute(DatabaseConstants.createReadingProgressTable);
    await db.execute(DatabaseConstants.createBookmarksTable);
    await db.execute(DatabaseConstants.createHighlightsTable);
    await db.execute(DatabaseConstants.createHighlightsIndex);
    debugPrint('[DatabaseHelper] Created schema v$version');
  }

  /// Incremental migrations.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
        '[DatabaseHelper] Upgrading schema v$oldVersion → v$newVersion');

    if (oldVersion < 2) {
      // v1 → v2: add file_path column.
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
            'ADD COLUMN ${DatabaseConstants.columnFilePath} TEXT',
      );
    }

    if (oldVersion < 3) {
      // v2 → v3: add title column.
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
            'ADD COLUMN ${DatabaseConstants.columnTitle} TEXT',
      );
    }

    if (oldVersion < 4) {
      // v3 → v4: add highlights table and index.
      await db.execute(DatabaseConstants.createHighlightsTable);
      await db.execute(DatabaseConstants.createHighlightsIndex);
    }

    debugPrint('[DatabaseHelper] Schema upgrade complete → v$newVersion');
  }
}