import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/bookmark.dart';

/// Service layer for all [Bookmark] persistence operations.
///
/// All database access is routed through the [DatabaseHelper] singleton so the
/// connection is shared and never opened more than once.
///
/// Usage:
/// ```dart
/// final service = BookmarkService.instance;
/// final id = await service.addBookmark(Bookmark.create(pdfId: 'doc1', page: 3));
/// ```
class BookmarkService {
  BookmarkService._internal();

  /// Package-scoped singleton.
  static final BookmarkService instance = BookmarkService._internal();

  /// Convenience accessor — avoids repeating `DatabaseHelper.instance` inline.
  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Write operations
  // ---------------------------------------------------------------------------

  /// Inserts a new [Bookmark] and returns its auto-incremented row id.
  ///
  /// Uses `ConflictAlgorithm.abort` (sqflite default) so duplicate inserts
  /// surface as errors rather than silently overwriting data. If you need
  /// idempotent upsert behaviour, use `ConflictAlgorithm.replace` instead.
  ///
  /// Throws a [BookmarkServiceException] on any database error.
  Future<int> addBookmark(Bookmark bookmark) async {
    try {
      final db = await _db;
      final rowId = await db.insert(
        DatabaseConstants.tableBookmarks,
        bookmark.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return rowId;
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'addBookmark failed for pdfId="${bookmark.pdfId}", page=${bookmark.page}.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Read operations
  // ---------------------------------------------------------------------------

  /// Returns all bookmarks for [pdfId] ordered by page number ascending.
  ///
  /// Returns an empty list when no bookmarks exist for the given document.
  /// Throws a [BookmarkServiceException] on any database or deserialisation
  /// error.
  Future<List<Bookmark>> getBookmarks(String pdfId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableBookmarks,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        orderBy: '${DatabaseConstants.columnPage} ASC',
      );

      return rows.map(Bookmark.fromMap).toList(growable: false);
    } on BookmarkServiceException {
      rethrow;
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'getBookmarks failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      // Catches FormatException from Bookmark.fromMap.
      throw BookmarkServiceException(
        'getBookmarks — deserialisation failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete operations
  // ---------------------------------------------------------------------------

  /// Deletes the bookmark identified by [id].
  ///
  /// Returns `true` if a row was deleted, `false` if no matching record
  /// existed.
  /// Throws a [BookmarkServiceException] on any database error.
  Future<bool> removeBookmark(int id) async {
    try {
      final db = await _db;
      final affected = await db.delete(
        DatabaseConstants.tableBookmarks,
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'removeBookmark failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all bookmarks belonging to [pdfId] inside a single transaction.
  ///
  /// Throws a [BookmarkServiceException] on any database error; the
  /// transaction is rolled back automatically by sqflite on failure.
  Future<void> clearBookmarks(String pdfId) async {
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.delete(
          DatabaseConstants.tableBookmarks,
          where: '${DatabaseConstants.columnPdfId} = ?',
          whereArgs: [pdfId],
        );
      });
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'clearBookmarks failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes **all** bookmark records across every document inside a single
  /// transaction.
  ///
  /// This is a destructive, unrecoverable operation — use only in explicit
  /// "clear all data" user flows or test teardown.
  ///
  /// Throws a [BookmarkServiceException] on any database error; the
  /// transaction is rolled back automatically by sqflite on failure.
  Future<void> clearAllBookmarks() async {
    try {
      final db = await _db;
      await db.transaction((txn) async {
        await txn.delete(DatabaseConstants.tableBookmarks);
      });
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'clearAllBookmarks failed.',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Exception type
// ---------------------------------------------------------------------------

/// Thrown by [BookmarkService] when a database operation cannot be completed.
///
/// Always wraps the original [cause] so callers can inspect the root error
/// without depending on sqflite's internal exception hierarchy.
class BookmarkServiceException implements Exception {
  const BookmarkServiceException(
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
    final buffer = StringBuffer('BookmarkServiceException: $message');
    if (cause != null) buffer.write('\nCause: $cause');
    return buffer.toString();
  }
}