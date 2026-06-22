import 'package:sqflite/sqflite.dart';

import '../constants/database_constants.dart';
import '../database/database_helper.dart';
import '../models/note.dart';

/// SQLite-backed persistence service for [Note] records.
///
/// Notes are text-anchored (v2.7.0): each note carries the selected text and
/// its bounding rects. All CRUD here returns plain values/lists; the
/// controller layer owns the in-memory cache and notifier plumbing.
class NoteService {
  NoteService._internal();
  static final NoteService instance = NoteService._internal();

  Future<Database> get _db => DatabaseHelper.instance.database;

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Inserts a new note and returns its auto-incremented row id.
  ///
  /// Throws [NoteServiceException] if [noteText] is empty.
  Future<int> addNote(Note note) async {
    if (note.noteText.trim().isEmpty) {
      throw const NoteServiceException('Cannot save an empty note.');
    }
    try {
      final db = await _db;
      return await db.insert(
        DatabaseConstants.tableNotes,
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'addNote failed for pdfId="${note.pdfId}", page=${note.page}.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Updates the [noteText] and [updatedAt] of an existing note.
  /// Returns `true` if a row was updated.
  Future<bool> updateNote(int id, String noteText) async {
    if (noteText.trim().isEmpty) {
      throw const NoteServiceException('Cannot save an empty note.');
    }
    try {
      final db = await _db;
      final affected = await db.update(
        DatabaseConstants.tableNotes,
        {
          DatabaseConstants.columnNoteText: noteText,
          DatabaseConstants.columnUpdatedAt:
          DateTime.now().toUtc().toIso8601String(),
        },
        where:     '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'updateNote failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns all notes for [pdfId] ordered by page ascending, then most
  /// recently updated first within the same page.
  Future<List<Note>> getNotes(String pdfId) async {
    try {
      final db   = await _db;
      final rows = await db.query(
        DatabaseConstants.tableNotes,
        where:     '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
        orderBy:   '${DatabaseConstants.columnPage} ASC, '
            '${DatabaseConstants.columnUpdatedAt} DESC',
      );
      return rows.map(Note.fromMap).toList(growable: false);
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'getNotes failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    } catch (e, st) {
      throw NoteServiceException(
        'getNotes — deserialisation failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Returns all notes for [pdfId] on a single [page] (zero-based).
  Future<List<Note>> getNotesForPage(String pdfId, int page) async {
    try {
      final db   = await _db;
      final rows = await db.query(
        DatabaseConstants.tableNotes,
        where:     '${DatabaseConstants.columnPdfId} = ? '
            'AND ${DatabaseConstants.columnPage} = ?',
        whereArgs: [pdfId, page],
        orderBy:   '${DatabaseConstants.columnUpdatedAt} DESC',
      );
      return rows.map(Note.fromMap).toList(growable: false);
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'getNotesForPage failed for pdfId="$pdfId", page=$page.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Deletes the note identified by [id]. Returns `true` if deleted.
  Future<bool> removeNote(int id) async {
    try {
      final db       = await _db;
      final affected = await db.delete(
        DatabaseConstants.tableNotes,
        where:     '${DatabaseConstants.columnId} = ?',
        whereArgs: [id],
      );
      return affected > 0;
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'removeNote failed for id=$id.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all notes for [pdfId].
  Future<void> clearNotes(String pdfId) async {
    try {
      final db = await _db;
      await db.delete(
        DatabaseConstants.tableNotes,
        where:     '${DatabaseConstants.columnPdfId} = ?',
        whereArgs: [pdfId],
      );
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
        'clearNotes failed for pdfId="$pdfId".',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deletes all note records across every document.
  Future<void> clearAllNotes() async {
    try {
      final db = await _db;
      await db.delete(DatabaseConstants.tableNotes);
    } on DatabaseException catch (e, st) {
      throw NoteServiceException(
          'clearAllNotes failed.', cause: e, stackTrace: st);
    }
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class NoteServiceException implements Exception {
  const NoteServiceException(this.message, {this.cause, this.stackTrace});

  final String      message;
  final Object?     cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final b = StringBuffer('NoteServiceException: $message');
    if (cause != null) b.write('\nCause: $cause');
    return b.toString();
  }
}