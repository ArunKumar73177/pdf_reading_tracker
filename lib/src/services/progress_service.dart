import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/reading_progress.dart';

/// Service layer for all [ReadingProgress] persistence operations.
///
/// Every public method is safe to call from any isolate that has access to the
/// main Flutter engine (sqflite requirement). All database access is routed
/// through the [DatabaseHelper] singleton so the connection is shared and
/// never opened more than once.
///
/// Usage:
/// ```dart
/// final service = ProgressService.instance;
/// final id = await service.saveProgress(ReadingProgress.create(...));
/// ```
class ProgressService {
  ProgressService._internal();

  /// Package-scoped singleton.
  static final ProgressService instance = ProgressService._internal();

  /// Convenience accessor — avoids repeating `DatabaseHelper.instance` inline.
  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Write operations
  // ---------------------------------------------------------------------------

  /// Inserts or replaces a [ReadingProgress] record and returns the row id.
  ///
  /// Uses `ConflictAlgorithm.replace` so callers can treat INSERT and UPDATE
  /// identically — the unique index on `pdf_id` enforces one row per document.
  ///
  /// Throws a [ProgressServiceException] on any database error.
  Future<int> saveProgress(ReadingProgress progress) async {
    try {
      final db = await _db;
      final existing = await db.query(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [progress.pdfId],
        limit: 1,
      );

      if (existing.isEmpty) {
        return await db.insert(
          DatabaseConstants.tableReadingProgress,
          progress.toMap(),
        );
      }

      await db.update(
        DatabaseConstants.tableReadingProgress,
        progress.toMap(),
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [progress.pdfId],
      );

      return existing.first[DatabaseConstants.columnId] as int;
    } on DatabaseException catch (e, st) {
      throw ProgressServiceException(
        'saveProgress failed for pdfId="${progress.pdfId}".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Read operations
  // ---------------------------------------------------------------------------

  /// Returns the [ReadingProgress] for [pdfId], or `null` if no record exists.
  ///
  /// Throws a [ProgressServiceException] on any database or deserialisation
  /// error.
  Future<ReadingProgress?> getProgress(String pdfId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        limit: 1,
      );

      if (rows.isEmpty) return null;
      return ReadingProgress.fromMap(rows.first);
    } on ProgressServiceException {
      rethrow;
    } on DatabaseException catch (e, st) {
      throw ProgressServiceException(
        'getProgress failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      // Catches FormatException from ReadingProgress.fromMap.
      throw ProgressServiceException(
        'getProgress — deserialisation failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Returns every [ReadingProgress] record ordered by most-recently read first.
  ///
  /// Returns an empty list when no records exist.
  /// Throws a [ProgressServiceException] on any database or deserialisation
  /// error.
  Future<List<ReadingProgress>> getAllProgress() async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        orderBy: '${DatabaseConstants.columnLastReadAt} DESC',
      );

      return rows.map(ReadingProgress.fromMap).toList(growable: false);
    } on ProgressServiceException {
      rethrow;
    } on DatabaseException catch (e, st) {
      throw ProgressServiceException(
        'getAllProgress failed.',
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw ProgressServiceException(
        'getAllProgress — deserialisation failed.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete operations
  // ---------------------------------------------------------------------------

  /// Deletes the [ReadingProgress] record for [pdfId].
  ///
  /// Returns `true` if a row was deleted, `false` if no matching record
  /// existed. The associated bookmarks are removed automatically by the
  /// `ON DELETE CASCADE` foreign-key constraint defined on the bookmarks table.
  ///
  /// Throws a [ProgressServiceException] on any database error.
  Future<bool> deleteProgress(String pdfId) async {
    try {
      final db = await _db;
      final affected = await db.delete(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw ProgressServiceException(
        'deleteProgress failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes **all** reading-progress records (and their cascaded bookmarks)
  /// inside a single transaction.
  ///
  /// This is a destructive, unrecoverable operation — use only in explicit
  /// "clear all data" user flows or test teardown.
  ///
  /// Throws a [ProgressServiceException] on any database error; the
  /// transaction is rolled back automatically by sqflite on failure.
  Future<void> clearAllProgress() async {
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.delete(DatabaseConstants.tableReadingProgress);
      });
    } on DatabaseException catch (e, st) {
      throw ProgressServiceException(
        'clearAllProgress failed.',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Exception type
// ---------------------------------------------------------------------------

/// Thrown by [ProgressService] when a database operation cannot be completed.
///
/// Always wraps the original [cause] so callers can inspect the root error
/// without depending on sqflite's internal exception hierarchy.
class ProgressServiceException implements Exception {
  const ProgressServiceException(
      this.message, {
        this.cause,
        this.stackTrace,
      });

  /// Human-readable description of what failed.
  final String message;

  /// The underlying error (typically a [DatabaseException] or [FormatException]).
  final Object? cause;

  /// Stack trace captured at the throw site.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('ProgressServiceException: $message');
    if (cause != null) buffer.write('\nCause: $cause');
    return buffer.toString();
  }
}