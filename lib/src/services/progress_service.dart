import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/reading_progress.dart';

/// Thrown by [ProgressService] when a database operation fails.
class ProgressServiceException implements Exception {
  const ProgressServiceException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProgressServiceException: $message'
      '${cause != null ? '\nCause: $cause' : ''}';
}

/// SQLite-backed service for reading progress records.
///
/// **v2.1.1 changes**
///
/// Bug 6 fix — `getRecentlyRead`:
///   The previous query filtered `total_pages > 0`, which excluded PDFs that
///   were opened but whose renderer hadn't yet reported the page count (or
///   whose first `onRender` fired after the user left the screen).  The filter
///   is removed; the controller now writes an initial record in `init()` so
///   any opened PDF always appears in Recent PDFs.
///
///   The `lastReadAt` ordering naturally puts newest entries first, so the
///   list is still useful without the total_pages guard.
class ProgressService {
  ProgressService._();
  static final instance = ProgressService._();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Upserts [progress] and returns the SQLite row id.
  Future<int> saveProgress(ReadingProgress progress) async {
    try {
      final db = await _db;
      return await db.insert(
        DatabaseConstants.tableReadingProgress,
        progress.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw ProgressServiceException('Failed to save progress', cause: e);
    }
  }

  /// Returns the progress for [pdfId], or `null` if never opened.
  Future<ReadingProgress?> getProgress(String pdfId) async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        limit: 1,
      );
      return rows.isEmpty ? null : ReadingProgress.fromMap(rows.first);
    } catch (e) {
      throw ProgressServiceException('Failed to get progress', cause: e);
    }
  }

  /// Returns an existing [ReadingProgress] for [pdfId], or creates and returns
  /// a fresh zero-progress record if none exists.
  ///
  /// Single DB round-trip for warm opens (record already exists).
  Future<ReadingProgress> getOrCreate({
    required String pdfId,
    required String pdfTitle,
    String? onDeviceFilePath,
  }) async {
    try {
      final db = await _db;

      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final existing = ReadingProgress.fromMap(rows.first);
        // Keep filePath in sync if the user moved and re-picked the file.
        if (onDeviceFilePath != null &&
            existing.filePath != onDeviceFilePath) {
          final updated = existing.copyWith(filePath: onDeviceFilePath);
          await db.insert(
            DatabaseConstants.tableReadingProgress,
            updated.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return updated;
        }
        return existing;
      }

      // First open — create anchor row.
      final fresh = ReadingProgress.create(
        pdfId: pdfId,
        currentPage: 0,
        totalPages: 0,
        title: pdfTitle,
        filePath: onDeviceFilePath,
      );
      await db.insert(
        DatabaseConstants.tableReadingProgress,
        fresh.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return fresh;
    } catch (e) {
      throw ProgressServiceException('Failed to get-or-create progress',
          cause: e);
    }
  }

  /// Returns all progress records, most-recently-read first.
  Future<List<ReadingProgress>> getAllProgress() async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        orderBy: '${DatabaseConstants.columnLastReadAt} DESC',
      );
      return rows.map(ReadingProgress.fromMap).toList();
    } catch (e) {
      throw ProgressServiceException('Failed to get all progress', cause: e);
    }
  }

  /// Returns up to [limit] most-recently-read records, ordered by
  /// `last_read_at DESC`.
  ///
  /// **v2.1.1 change**: the previous `total_pages > 0` filter is removed.
  /// PDFs are now written to the DB the moment they are opened (even before
  /// the renderer reports the page count), so filtering by `total_pages`
  /// would hide freshly-opened PDFs.  The `lastReadAt` ordering is sufficient
  /// to surface the most relevant entries.
  ///
  /// Callers that want to exclude never-rendered PDFs can filter client-side:
  /// ```dart
  /// final all = await getRecentlyRead();
  /// final rendered = all.where((p) => p.totalPages > 0).toList();
  /// ```
  Future<List<ReadingProgress>> getRecentlyRead({int limit = 20}) async {
    try {
      final db = await _db;
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        orderBy: '${DatabaseConstants.columnLastReadAt} DESC',
        limit: limit,
      );
      return rows.map(ReadingProgress.fromMap).toList();
    } catch (e) {
      throw ProgressServiceException('Failed to get recently read', cause: e);
    }
  }

  /// Deletes the progress record for [pdfId]. Returns `true` if a row was
  /// deleted.
  Future<bool> deleteProgress(String pdfId) async {
    try {
      final db = await _db;
      final count = await db.delete(
        DatabaseConstants.tableReadingProgress,
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
      );
      return count > 0;
    } catch (e) {
      throw ProgressServiceException('Failed to delete progress', cause: e);
    }
  }

  /// Deletes all progress records.
  Future<void> clearAllProgress() async {
    try {
      final db = await _db;
      await db.delete(DatabaseConstants.tableReadingProgress);
    } catch (e) {
      throw ProgressServiceException('Failed to clear progress', cause: e);
    }
  }
}