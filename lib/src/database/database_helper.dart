import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';

/// Singleton that owns the full SQLite lifecycle for [pdf_reading_tracker].
///
/// Never construct directly. Always access via [DatabaseHelper.instance].
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Database? _db;
  Completer<Database>? _openCompleter;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    if (_openCompleter != null) return _openCompleter!.future;

    _openCompleter = Completer<Database>();
    try {
      final db = await _initDatabase();
      _db = db;
      _openCompleter!.complete(db);
      return db;
    } catch (e, st) {
      _openCompleter!.completeError(e, st);
      _openCompleter = null;
      _db = null;
      rethrow;
    }
  }

  Future<void> close() async {
    if (_openCompleter != null && !_openCompleter!.isCompleted) {
      try { await _openCompleter!.future; } catch (_) {}
    }
    if (_db != null && _db!.isOpen) await _db!.close();
    _db = null;
    _openCompleter = null;
  }

  Future<void> deleteDatabase() async {
    await close();
    final path = await _resolveDatabasePath();
    await databaseFactory.deleteDatabase(path);
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<Database> _initDatabase() async {
    final path = await _resolveDatabasePath();
    return openDatabase(
      path,
      version: DatabaseConstants.kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
      onOpen: _onOpen,
    );
  }

  Future<String> _resolveDatabasePath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, DatabaseConstants.kDatabaseName);
    } catch (_) {
      return p.join(await getDatabasesPath(), DatabaseConstants.kDatabaseName);
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite lifecycle callbacks
  // ---------------------------------------------------------------------------

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    if (!kIsWeb) await db.rawQuery('PRAGMA journal_mode = WAL;');
  }

  /// Full v4 schema for fresh installs — never needs migrations.
  Future<void> _onCreate(Database db, int version) async {
    await _createReadingProgressTable(db);
    await _createBookmarksTable(db);
    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int target = oldVersion + 1; target <= newVersion; target++) {
      switch (target) {
        case 2:
          await _migrateV1ToV2(db);
        case 3:
        // v3 was a no-op bump in the previous session — nothing to migrate.
          break;
        case 4:
          await _migrateV3ToV4(db);
        default:
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DDL — table creation (always latest schema)
  // ---------------------------------------------------------------------------

  Future<void> _createReadingProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableReadingProgress} (
        ${DatabaseConstants.columnId}           INTEGER  PRIMARY KEY AUTOINCREMENT,
        ${DatabaseConstants.columnPdfId}        TEXT     NOT NULL,
        ${DatabaseConstants.columnCurrentPage}  INTEGER  NOT NULL DEFAULT 0,
        ${DatabaseConstants.columnTotalPages}   INTEGER  NOT NULL DEFAULT 0,
        ${DatabaseConstants.columnProgressPct}  REAL     NOT NULL DEFAULT 0.0,
        ${DatabaseConstants.columnLastReadAt}   TEXT     NOT NULL,
        ${DatabaseConstants.columnCreatedAt}    TEXT     NOT NULL,
        ${DatabaseConstants.columnTitle}        TEXT,
        ${DatabaseConstants.columnFilePath}     TEXT,
        UNIQUE(${DatabaseConstants.columnPdfId})
      );
    ''');
  }

  Future<void> _createBookmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableBookmarks} (
        ${DatabaseConstants.columnId}        INTEGER PRIMARY KEY AUTOINCREMENT,
        ${DatabaseConstants.columnPdfId}     TEXT    NOT NULL,
        ${DatabaseConstants.columnPage}      INTEGER NOT NULL,
        ${DatabaseConstants.columnNote}      TEXT,
        ${DatabaseConstants.columnCreatedAt} TEXT    NOT NULL,
        UNIQUE(${DatabaseConstants.columnPdfId}, ${DatabaseConstants.columnPage}),
        FOREIGN KEY (${DatabaseConstants.columnPdfId})
          REFERENCES ${DatabaseConstants.tableReadingProgress}(${DatabaseConstants.columnPdfId})
          ON DELETE CASCADE
      );
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rp_pdf_id
        ON ${DatabaseConstants.tableReadingProgress}(${DatabaseConstants.columnPdfId});
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rp_last_read
        ON ${DatabaseConstants.tableReadingProgress}(${DatabaseConstants.columnLastReadAt});
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bm_pdf_id
        ON ${DatabaseConstants.tableBookmarks}(${DatabaseConstants.columnPdfId});
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bm_pdf_id_page
        ON ${DatabaseConstants.tableBookmarks}
          (${DatabaseConstants.columnPdfId}, ${DatabaseConstants.columnPage});
    ''');
  }

  // ---------------------------------------------------------------------------
  // Migrations
  // ---------------------------------------------------------------------------

  /// v1 → v2: add nullable [columnTitle] to [tableReadingProgress].
  Future<void> _migrateV1ToV2(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseConstants.tableReadingProgress});',
    );
    final exists = columns.any((r) => r['name'] == DatabaseConstants.columnTitle);
    if (!exists) {
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
            'ADD COLUMN ${DatabaseConstants.columnTitle} TEXT;',
      );
    }
  }

  /// v3 → v4: add nullable [columnFilePath] to [tableReadingProgress].
  ///
  /// Existing rows receive NULL which correctly means "asset-backed PDF".
  /// The PRAGMA guard makes this idempotent if ever called twice.
  Future<void> _migrateV3ToV4(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseConstants.tableReadingProgress});',
    );
    final exists =
    columns.any((r) => r['name'] == DatabaseConstants.columnFilePath);
    if (!exists) {
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
            'ADD COLUMN ${DatabaseConstants.columnFilePath} TEXT;',
      );
    }
    // Add the last_read index now that we query by it for recent PDFs.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rp_last_read
        ON ${DatabaseConstants.tableReadingProgress}(${DatabaseConstants.columnLastReadAt});
    ''');
  }
}