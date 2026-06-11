import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';

/// Singleton that owns the full SQLite lifecycle for [pdf_reading_tracker].
///
/// **Never construct directly.** Always access via [DatabaseHelper.instance]:
/// ```dart
/// final db = await DatabaseHelper.instance.database;
/// ```
///
/// ### Async / concurrency safety
/// The first call to [database] begins initialisation and stores a
/// [Completer] immediately. Every concurrent caller that arrives while init
/// is in flight receives the *same* [Future] from that completer, so
/// [openDatabase] is invoked exactly once regardless of how many services
/// access the DB in parallel at startup.
///
/// On [close] or [deleteDatabase] the completer is set back to `null` only
/// after it has been completed, so no in-flight caller is ever left with a
/// future that never resolves.
class DatabaseHelper {
  DatabaseHelper._internal();

  /// The single, package-scoped instance.
  static final DatabaseHelper instance = DatabaseHelper._internal();

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Cached open connection. Non-null after first successful [_initDatabase].
  Database? _db;

  /// Holds the in-flight init future so concurrent callers can piggyback.
  /// Nulled out only after it has been completed (success or error) and the
  /// caller has explicitly reset state via [close] / [deleteDatabase].
  Completer<Database>? _openCompleter;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the open [Database], initialising it lazily on first access.
  ///
  /// Safe to call concurrently: all callers receive the same [Future] while
  /// init is in progress.
  Future<Database> get database async {
    // ── Fast path ─────────────────────────────────────────────────────────────
    if (_db != null && _db!.isOpen) return _db!;

    // ── Init already in flight — piggyback on existing completer ─────────────
    if (_openCompleter != null) return _openCompleter!.future;

    // ── We are the first caller — own the init ────────────────────────────────
    // Create the completer BEFORE the first await so any concurrent caller
    // that enters this getter while we are suspended hits the piggyback branch
    // above, not the "first caller" branch again.
    _openCompleter = Completer<Database>();

    try {
      final db = await _initDatabase();
      _db = db;
      // Complete the completer so every waiting caller is unblocked.
      _openCompleter!.complete(db);
      return db;
    } catch (e, st) {
      // Unblock every waiting caller with the same error.
      _openCompleter!.completeError(e, st);
      // Clear state so callers can retry once the underlying problem is fixed
      // (e.g. storage permission granted after the first attempt failed).
      _openCompleter = null;
      _db = null;
      rethrow;
    }
  }

  /// Closes the connection gracefully and resets state so the next call to
  /// [database] triggers a fresh initialisation.
  ///
  /// Safe to call when the database is already closed or was never opened.
  Future<void> close() async {
    // If init is still in flight wait for it before closing, otherwise the
    // completer's future listeners would never resolve.
    if (_openCompleter != null && !_openCompleter!.isCompleted) {
      try {
        await _openCompleter!.future;
      } catch (_) {
        // Init failed; nothing to close.
      }
    }

    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }

    _db = null;
    _openCompleter = null;
  }

  /// Deletes the database file from disk. **Completely destructive.**
  ///
  /// Use only in tests or an explicit "factory reset" user flow.
  /// Closes the connection first to avoid file-lock issues on Windows/Linux.
  Future<void> deleteDatabase() async {
    await close();
    final path = await _resolveDatabasePath();
    await databaseFactory.deleteDatabase(path);
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Opens (or creates) the database file and applies any pending migrations.
  Future<Database> _initDatabase() async {
    final path = await _resolveDatabasePath();

    return openDatabase(
      path,
      version: DatabaseConstants.kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      // Downgrade means the user installed an older binary over a newer one.
      // Wiping and recreating is safer than attempting to reverse migrations.
      onDowngrade: onDatabaseDowngradeDelete,
      onOpen: _onOpen,
    );
  }

  /// Returns the platform-appropriate absolute path for the database file.
  ///
  /// Uses [getApplicationDocumentsDirectory] on mobile/desktop — this
  /// directory survives app updates. Falls back to sqflite's own
  /// [getDatabasesPath] in unit-test environments where `path_provider`
  /// is unavailable.
  Future<String> _resolveDatabasePath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return p.join(dir.path, DatabaseConstants.kDatabaseName);
    } catch (_) {
      return p.join(
        await getDatabasesPath(),
        DatabaseConstants.kDatabaseName,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite lifecycle callbacks
  // ---------------------------------------------------------------------------

  /// Fired by sqflite on every successful open, *after* onCreate / onUpgrade.
  ///
  /// #### Why two different sqflite APIs for two PRAGMAs?
  ///
  /// sqflite enforces a strict rule inherited from Android's SQLiteDatabase:
  /// **`execute()` must only be used for SQL that returns no rows**.
  /// Any statement that produces a result set — even a single-row PRAGMA —
  /// must go through `rawQuery()` or `query()`.
  ///
  /// | PRAGMA                    | Returns rows? | Correct API     |
  /// |---------------------------|---------------|-----------------|
  /// | `PRAGMA foreign_keys = ON`| No            | `execute()` ✅  |
  /// | `PRAGMA journal_mode = WAL`| Yes (1 row)  | `rawQuery()` ✅ |
  ///
  /// Calling `execute('PRAGMA journal_mode = WAL;')` throws:
  /// > "Queries can be performed using SQLiteDatabase query or rawQuery methods only."
  ///
  /// #### Platform matrix
  /// `foreign_keys` must be set on every new connection (not persisted).
  /// `journal_mode = WAL` is persisted in the DB file header once set, so
  /// re-applying it on every open is idempotent and costs one cheap read.
  /// WAL requires a real filesystem — skipped on Flutter Web (in-memory FS).
  Future<void> _onOpen(Database db) async {
    // Setter-only PRAGMA: produces no rows → execute() is correct.
    await db.execute('PRAGMA foreign_keys = ON;');

    // Getter/setter PRAGMA: always returns one result row → must use rawQuery().
    // Skipped on Flutter Web where WAL is unsupported (in-memory virtual FS).
    if (!kIsWeb) {
      await db.rawQuery('PRAGMA journal_mode = WAL;');
    }
  }

  /// Called by sqflite when the database file is brand-new (version 0 → N).
  ///
  /// Always creates the *latest* schema in full so a fresh install never
  /// needs to execute any migration steps.
  Future<void> _onCreate(Database db, int version) async {
    await _createReadingProgressTable(db);
    await _createBookmarksTable(db);
    await _createIndexes(db);
  }

  /// Called by sqflite when the on-disk schema version < [kDatabaseVersion].
  ///
  /// The `for` loop ensures every intermediate migration runs in order even
  /// when a user upgrades across multiple versions at once (e.g. v1 → v3).
  /// Each `case` is independent — no intentional fall-through is needed
  /// because every migration is awaited inside its own `case` block.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int target = oldVersion + 1; target <= newVersion; target++) {
      switch (target) {
        case 2:
          await _migrateV1ToV2(db);
          break;
      // ── Future migrations ──────────────────────────────────────────────
      // case 3:
      //   await _migrateV2ToV3(db);
      //   break;
        default:
        // Unknown version — nothing to do. This branch is unreachable as
        // long as every version bump is paired with a migration case above.
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // DDL — table & index creation
  // ---------------------------------------------------------------------------

  /// Creates [tableReadingProgress] with the *full* v2 schema.
  ///
  /// The [columnTitle] column is included here so that fresh installs at
  /// version 2 never go through the migration path.
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
        UNIQUE(${DatabaseConstants.columnPdfId})
      );
    ''');
  }

  /// Creates [tableBookmarks].
  ///
  /// The `FOREIGN KEY … ON DELETE CASCADE` removes all bookmarks for a
  /// document automatically when its [tableReadingProgress] row is deleted.
  /// This only takes effect because [_onOpen] enables `foreign_keys = ON`.
  Future<void> _createBookmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseConstants.tableBookmarks} (
  ${DatabaseConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
  ${DatabaseConstants.columnPdfId} TEXT NOT NULL,
  ${DatabaseConstants.columnPage} INTEGER NOT NULL,
  ${DatabaseConstants.columnNote} TEXT,
  ${DatabaseConstants.columnCreatedAt} TEXT NOT NULL,

  UNIQUE(
    ${DatabaseConstants.columnPdfId},
    ${DatabaseConstants.columnPage}
  ),

  FOREIGN KEY (${DatabaseConstants.columnPdfId})
    REFERENCES ${DatabaseConstants.tableReadingProgress}
      (${DatabaseConstants.columnPdfId})
    ON DELETE CASCADE
);
    ''');
  }

  /// Creates indexes that accelerate the two most common query patterns:
  /// per-document lookup and page-sorted bookmark listing.
  Future<void> _createIndexes(Database db) async {
    // Single-column index on reading_progress for getProgress() / deleteProgress().
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rp_pdf_id
        ON ${DatabaseConstants.tableReadingProgress}
          (${DatabaseConstants.columnPdfId});
    ''');

    // Single-column index on bookmarks for getBookmarks() / clearBookmarks().
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bm_pdf_id
        ON ${DatabaseConstants.tableBookmarks}
          (${DatabaseConstants.columnPdfId});
    ''');

    // Composite index for getBookmarks() ORDER BY page — avoids a full-table
    // scan on large bookmark sets.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bm_pdf_id_page
        ON ${DatabaseConstants.tableBookmarks}
          (${DatabaseConstants.columnPdfId}, ${DatabaseConstants.columnPage});
    ''');
  }

  // ---------------------------------------------------------------------------
  // Migrations
  // ---------------------------------------------------------------------------

  /// **v1 → v2**: Adds the nullable [columnTitle] column to
  /// [tableReadingProgress].
  ///
  /// #### Why PRAGMA table_info guard?
  /// `ALTER TABLE … ADD COLUMN` throws `duplicate column name` if the column
  /// already exists. The PRAGMA check makes the migration idempotent — safe
  /// to re-run in tests that reuse an on-disk fixture, and safe if
  /// [_migrateV1ToV2] were ever called twice due to a future refactor.
  ///
  /// #### Data impact on existing users
  /// Existing rows receive `NULL` for [columnTitle]. This is correct and safe
  /// because [ReadingProgress.title] is declared as `String?` in the model.
  /// No data loss. No app uninstall required.
  Future<void> _migrateV1ToV2(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(${DatabaseConstants.tableReadingProgress});',
    );

    final titleColumnExists =
    columns.any((row) => row['name'] == DatabaseConstants.columnTitle);

    if (!titleColumnExists) {
      await db.execute(
        'ALTER TABLE ${DatabaseConstants.tableReadingProgress} '
            'ADD COLUMN ${DatabaseConstants.columnTitle} TEXT;',
      );
    }
  }
}