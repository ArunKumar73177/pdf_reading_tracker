import '../constants/database_constants.dart';

/// Immutable value object representing a freestanding, page-scoped note.
///
/// Notes are independent of [Highlight] annotations — a user can add a note
/// to a page with or without any text selected. This is the model backing
/// the dedicated Notes Panel.
///
/// ### Page convention
/// [page] is **zero-based**, matching [Highlight.page] and
/// [ReadingProgress.currentPage] throughout this package.
class Note {
  const Note({
    this.id,
    required this.pdfId,
    required this.page,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Auto-incremented SQLite primary key. `null` before first insert.
  final int? id;

  /// Stable PDF identifier this note belongs to.
  final String pdfId;

  /// Zero-based page index this note is attached to.
  final int page;

  /// The note body. Never empty for a persisted row — callers must validate
  /// before calling [NoteService.addNote] / [NoteService.updateNote].
  final String text;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-modified timestamp. Equal to [createdAt] until first edit.
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  factory Note.create({
    required String pdfId,
    required int page,
    required String text,
  }) {
    final now = DateTime.now().toUtc();
    return Note(
      pdfId: pdfId,
      page: page,
      text: text,
      createdAt: now,
      updatedAt: now,
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Note copyWith({
    int? id,
    String? pdfId,
    int? page,
    String? text,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      pdfId: pdfId ?? this.pdfId,
      page: page ?? this.page,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId: pdfId,
      DatabaseConstants.columnPage: page,
      DatabaseConstants.columnNoteText: text,
      DatabaseConstants.columnCreatedAt: createdAt.toUtc().toIso8601String(),
      DatabaseConstants.columnUpdatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    try {
      return Note(
        id: map[DatabaseConstants.columnId] as int?,
        pdfId: map[DatabaseConstants.columnPdfId] as String,
        page: map[DatabaseConstants.columnPage] as int,
        text: map[DatabaseConstants.columnNoteText] as String,
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        updatedAt: DateTime.parse(
          map[DatabaseConstants.columnUpdatedAt] as String,
        ).toLocal(),
      );
    } catch (e) {
      throw FormatException('Note.fromMap failed. Cause: $e\nRow: $map');
    }
  }

  // ---------------------------------------------------------------------------
  // Equality & hashing
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Note) return false;
    return other.id == id &&
        other.pdfId == pdfId &&
        other.page == page &&
        other.text == text &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, pdfId, page, text, createdAt, updatedAt);

  @override
  String toString() => 'Note('
      'id: $id, pdfId: $pdfId, page: $page, '
      'text: "${text.length > 30 ? '${text.substring(0, 30)}...' : text}", '
      'updatedAt: $updatedAt)';
}