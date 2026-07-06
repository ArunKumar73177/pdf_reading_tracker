import '../constants/database_constants.dart';

/// Immutable value object representing a bookmark placed on a specific page of
/// a PDF document.
///
/// Persisted to and restored from SQLite via [toMap] / [fromMap].
class Bookmark {
  /// Auto-incremented primary key. `null` before the record is first inserted.
  final int? id;

  /// Identifier of the PDF this bookmark belongs to. References
  /// `reading_progress.pdf_id` with ON DELETE CASCADE.
  final String pdfId;

  /// Zero-based page index where the bookmark was placed.
  final int page;

  /// Optional user-supplied annotation for this bookmark.
  final String? note;

  /// UTC timestamp when this bookmark was created.
  final DateTime createdAt;

  const Bookmark({
    this.id,
    required this.pdfId,
    required this.page,
    this.note,
    required this.createdAt,
  }) : assert(page >= 0, 'page must be ≥ 0');

  // ---------------------------------------------------------------------------
  // Convenience factory
  // ---------------------------------------------------------------------------

  /// Creates a new [Bookmark] with [createdAt] set to [DateTime.now] (UTC).
  factory Bookmark.create({
    required String pdfId,
    required int page,
    String? note,
  }) {
    return Bookmark(
      pdfId: pdfId,
      page: page,
      note: note,
      createdAt: DateTime.now().toUtc(),
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Bookmark copyWith({
    int? id,
    String? pdfId,
    int? page,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      pdfId: pdfId ?? this.pdfId,
      page: page ?? this.page,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// Converts this instance to a column→value map suitable for sqflite.
  ///
  /// [id] is omitted when `null` so sqflite auto-increments on INSERT.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId: pdfId,
      DatabaseConstants.columnPage: page,
      DatabaseConstants.columnNote: note,
      DatabaseConstants.columnCreatedAt: createdAt.toUtc().toIso8601String(),
    };
  }

  /// Deserialises a sqflite row map into a [Bookmark].
  ///
  /// Throws a [FormatException] if any required field is missing or carries an
  /// unexpected type, surfacing schema mismatches early.
  factory Bookmark.fromMap(Map<String, dynamic> map) {
    try {
      return Bookmark(
        id: map[DatabaseConstants.columnId] as int?,
        pdfId: map[DatabaseConstants.columnPdfId] as String,
        page: map[DatabaseConstants.columnPage] as int,
        note: map[DatabaseConstants.columnNote] as String?,
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
      );
    } catch (e) {
      throw FormatException(
        'Bookmark.fromMap failed — check column names and types. '
        'Cause: $e\nRow: $map',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Equality & hashing
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Bookmark) return false;

    return other.id == id &&
        other.pdfId == pdfId &&
        other.page == page &&
        other.note == note &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, pdfId, page, note, createdAt);

  // ---------------------------------------------------------------------------
  // Debugging
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return 'Bookmark('
        'id: $id, '
        'pdfId: $pdfId, '
        'page: $page, '
        'note: $note, '
        'createdAt: $createdAt'
        ')';
  }
}
