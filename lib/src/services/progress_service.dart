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
///
/// **v2.5.1 fix — cascading delete of bookmarks/highlights on every save:**
///   `reading_progress.pdf_id` is `UNIQUE`, and `bookmarks`/`highlights` both
///   declare `FOREIGN KEY (pdf_id) REFERENCES reading_progress (pdf_id)
///   ON DELETE CASCADE`, with `PRAGMA foreign_keys = ON` set in
///   [DatabaseHelper]. `db.insert(..., conflictAlgorithm:
///   ConflictAlgorithm.replace)` compiles to SQLite's `INSERT OR REPLACE`,
///   which — per SQLite's documented conflict resolution — **deletes** the
///   conflicting row before inserting the new one. Every such delete fired
///   the `ON DELETE CASCADE`, wiping all bookmarks and highlights for that
///   `pdf_id` on every progress save (and on every `getOrCreate` call whose
///   resolved file path differed from the stored one, which is effectively
///   every reopen through a file picker with a timestamped cache path).
///
///   Fixed by replacing every `INSERT OR REPLACE` against
///   `reading_progress` with an explicit `UPDATE` when a row already exists
///   for the `pdf_id`, falling back to a plain `INSERT` only when it does
///   not. This never deletes the existing row, so the FK cascade never
///   fires and bookmarks/highlights are preserved across saves and reopens.
class ProgressService {
  ProgressService._();
  static final instance = ProgressService._();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Internal upsert helper (no delete — never triggers ON DELETE CASCADE)
  // ---------------------------------------------------------------------------

  /// Inserts [progress] if no row exists for its `pdfId`, otherwise updates
  /// the existing row in place via `UPDATE ... WHERE pdf_id = ?`.
  ///
  /// Deliberately avoids `ConflictAlgorithm.replace` / `INSERT OR REPLACE`:
  /// against a `UNIQUE` column with `ON DELETE CASCADE` children
  /// (`bookmarks`, `highlights`), a replace-insert deletes the existing row
  /// first, which cascades and destroys those child rows. An `UPDATE`
  /// modifies the row in place and never triggers `ON DELETE`.
  Future<int> _upsert(ReadingProgress progress) async {
    final db = await _db;
    final map = progress.toMap();

    final affected = await db.update(
      DatabaseConstants.tableReadingProgress,
      map,
      where: '${DatabaseConstants.columnPdfId} = ?',
      whereArgs: [progress.pdfId],
    );

    if (affected > 0) {
      final rows = await db.query(
        DatabaseConstants.tableReadingProgress,
        columns: [DatabaseConstants.columnId],
        where: '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [progress.pdfId],
        limit: 1,
      );
      return rows.first[DatabaseConstants.columnId] as int;
    }

    // No existing row — safe to insert. Use abort (not replace) since we
    // already know there's no conflicting pdf_id row to worry about; abort
    // simply surfaces a genuine race as an error instead of silently
    // deleting+reinserting.
    return db.insert(
      DatabaseConstants.tableReadingProgress,
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Upserts [progress] and returns the SQLite row id.
  ///
  /// Never deletes the existing `reading_progress` row, so `bookmarks` and
  /// `highlights` rows tied to this `pdfId` via `ON DELETE CASCADE` are
  /// preserved.
  Future<int> saveProgress(ReadingProgress progress) async {
    try {
      return await _upsert(progress);
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
  /// Single DB round-trip for warm opens (record already exists, file path
  /// unchanged).
  ///
  /// **Fix (v2.5.1):** the file-path-sync branch now uses [_upsert] (an
  /// `UPDATE`, not `INSERT OR REPLACE`) so syncing `filePath` on reopen no
  /// longer deletes-then-reinserts the row and no longer cascades into
  /// `bookmarks`/`highlights`.
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
          await _upsert(updated);
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
      await _upsert(fresh);
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
  ///
  /// This is the one place an actual `DELETE` (and therefore the
  /// `ON DELETE CASCADE` into `bookmarks`/`highlights`) is intentional and
  /// correct: removing a PDF's progress should also remove its bookmarks
  /// and highlights.
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