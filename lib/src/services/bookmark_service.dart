import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/bookmark.dart';

/// Service layer for all [Bookmark] persistence operations.
class BookmarkService {
  BookmarkService._internal();
  static final BookmarkService instance = BookmarkService._internal();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Inserts a new [Bookmark] and returns its auto-incremented row id.
  ///
  /// Uses [ConflictAlgorithm.abort] so duplicate page-for-same-pdf inserts
  /// surface as errors rather than silently overwriting.
  Future<int> addBookmark(Bookmark bookmark) async {
    try {
      final db = await _db;
      return await db.insert(
        DatabaseConstants.tableBookmarks,
        bookmark.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'addBookmark failed for pdfId="${bookmark.pdfId}", page=${bookmark.page}.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Updates the [note] on an existing bookmark identified by [id].
  ///
  /// Pass `null` to [note] to clear an existing note.
  /// Returns `true` if a row was updated, `false` if no matching id was found.
  Future<bool> updateNote(int id, String? note) async {
    try {
      final db = await _db;
      final affected = await db.update(
        DatabaseConstants.tableBookmarks,
        {DatabaseConstants.columnNote: note},
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw BookmarkServiceException(
        'updateNote failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all bookmarks for [pdfId] ordered by page number ascending.
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
      throw BookmarkServiceException(
        'getBookmarks — deserialisation failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Deletes the bookmark identified by [id].
  ///
  /// Returns `true` if a row was deleted, `false` if no match was found.
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

  /// Deletes all bookmarks belonging to [pdfId].
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

  /// Deletes **all** bookmark records across every document.
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
// Exception
// ---------------------------------------------------------------------------

class BookmarkServiceException implements Exception {
  const BookmarkServiceException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final b = StringBuffer('BookmarkServiceException: $message');
    if (cause != null) b.write('\nCause: $cause');
    return b.toString();
  }
}
