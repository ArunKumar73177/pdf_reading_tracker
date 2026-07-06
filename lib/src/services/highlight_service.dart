import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/highlight.dart';

/// SQLite-backed persistence service for [Highlight] records.
///
/// All CRUD operations keep the in-memory list in [PdfViewerController] as the
/// source of truth; this service handles only durable storage.
///
/// ### v2.2.0 additions
/// - [updateAnnotationType] — lets callers change the visual type of a saved
///   annotation without deleting and re-inserting the row.
class HighlightService {
  HighlightService._internal();
  static final HighlightService instance = HighlightService._internal();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Inserts [highlight] and returns its auto-incremented row id.
  Future<int> addHighlight(Highlight highlight) async {
    try {
      final db = await _db;
      return await db.insert(
        DatabaseConstants.tableHighlights,
        highlight.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'addHighlight failed for pdfId="${highlight.pdfId}", '
        'page=${highlight.page}.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Updates the [note] field. Pass `null` to clear an existing note.
  /// Returns `true` if a row was updated.
  Future<bool> updateNote(int id, String? note) async {
    try {
      final db = await _db;
      final affected = await db.update(
        DatabaseConstants.tableHighlights,
        {DatabaseConstants.columnNote: note},
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'updateNote failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Updates the [colorValue] of a highlight.
  Future<bool> updateColor(int id, int colorValue) async {
    try {
      final db = await _db;
      final affected = await db.update(
        DatabaseConstants.tableHighlights,
        {DatabaseConstants.columnColorValue: colorValue},
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'updateColor failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Updates the [annotationType] of a saved annotation.
  /// Returns `true` if a row was updated.
  Future<bool> updateAnnotationType(int id, AnnotationType type) async {
    try {
      final db = await _db;
      final affected = await db.update(
        DatabaseConstants.tableHighlights,
        {DatabaseConstants.columnAnnotationType: type.dbValue},
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'updateAnnotationType failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all highlights for [pdfId] ordered by page ascending.
  Future<List<Highlight>> getHighlights(String pdfId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableHighlights,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        orderBy: '${DatabaseConstants.columnPage} ASC, '
            '${DatabaseConstants.columnCreatedAt} ASC',
      );
      return rows.map(Highlight.fromMap).toList(growable: false);
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'getHighlights failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw HighlightServiceException(
        'getHighlights — deserialisation failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Deletes the highlight identified by [id]. Returns `true` if deleted.
  Future<bool> removeHighlight(int id) async {
    try {
      final db = await _db;
      final affected = await db.delete(
        DatabaseConstants.tableHighlights,
        where: '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'removeHighlight failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all highlights on [page] (zero-based) for [pdfId].
  Future<void> clearHighlightsOnPage(String pdfId, int page) async {
    try {
      final db = await _db;
      await db.delete(
        DatabaseConstants.tableHighlights,
        where: '${DatabaseConstants.columnPdfId} = ? '
            'AND ${DatabaseConstants.columnPage} = ?',
        whereArgs: [pdfId, page],
      );
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'clearHighlightsOnPage failed for pdfId="$pdfId", page=$page.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all highlights for [pdfId].
  Future<void> clearHighlights(String pdfId) async {
    try {
      final db = await _db;
      await db.delete(
        DatabaseConstants.tableHighlights,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
      );
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'clearHighlights failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all highlight records across every document.
  Future<void> clearAllHighlights() async {
    try {
      final db = await _db;
      await db.delete(DatabaseConstants.tableHighlights);
    } on DatabaseException catch (e, st) {
      throw HighlightServiceException(
        'clearAllHighlights failed.',
        cause: e,
        stackTrace: st,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class HighlightServiceException implements Exception {
  const HighlightServiceException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final b = StringBuffer('HighlightServiceException: $message');
    if (cause != null) b.write('\nCause: $cause');
    return b.toString();
  }
}
