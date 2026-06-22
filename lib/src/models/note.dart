import '../constants/database_constants.dart';

// ---------------------------------------------------------------------------
// NoteRect — bounding rectangle in PDF page-space (same encoding as
// HighlightRect, kept separate to avoid a cross-model import dependency).
// ---------------------------------------------------------------------------

/// A bounding rectangle in PDF page-space coordinates.
///
/// Encoded identically to [HighlightRect]: `"left,top,right,bottom"`.
class NoteRect {
  const NoteRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width  => right  - left;
  double get height => bottom - top;

  String encode() => '$left,$top,$right,$bottom';

  factory NoteRect.fromString(String s) {
    final parts = s.split(',');
    if (parts.length != 4) {
      throw FormatException(
          'NoteRect.fromString: expected 4 values, got "$s"');
    }
    return NoteRect(
      left:   double.parse(parts[0]),
      top:    double.parse(parts[1]),
      right:  double.parse(parts[2]),
      bottom: double.parse(parts[3]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NoteRect) return false;
    return other.left   == left  && other.top    == top &&
        other.right  == right && other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'NoteRect(l:$left, t:$top, r:$right, b:$bottom)';
}

// ---------------------------------------------------------------------------
// Note — text-anchored page note (v2.7.0 architecture)
// ---------------------------------------------------------------------------

/// Immutable value object representing a user note anchored to a specific
/// text selection on a PDF page.
///
/// ### Design (v2.7.0)
/// Notes are no longer page-level items (which duplicated bookmark
/// functionality). A note is now always attached to a text selection:
///
/// - [selectedText] — the verbatim text the user had selected.
/// - [rectList]     — bounding rectangles of that selection in PDF
///                    page-space coordinates (same encoding as
///                    `Highlight.rectList`). Used to scroll to the
///                    annotation location when the user taps the note.
/// - [noteText]     — the user's written note.
///
/// ### Page convention
/// [page] is **zero-based**, matching [Highlight.page] and
/// [ReadingProgress.currentPage] throughout this package.
///
/// ### Encoding
/// [rectList] is serialised as a pipe-separated string of
/// `"left,top,right,bottom"` records, identical to the highlights table.
/// An empty [rectList] is valid (e.g., the user cleared the selection
/// between tap and save) — the note will still display, but no scroll-to
/// will be attempted.
class Note {
  const Note({
    this.id,
    required this.pdfId,
    required this.page,
    required this.noteText,
    required this.selectedText,
    required this.rectList,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Auto-incremented SQLite primary key. `null` before first insert.
  final int? id;

  /// Stable PDF identifier this note belongs to.
  final String pdfId;

  /// Zero-based page index this note is attached to.
  final int page;

  /// The user's note body. Never empty for a persisted row.
  final String noteText;

  /// The text the user had selected when creating this note.
  /// Empty string when the selection was lost before the note was saved.
  final String selectedText;

  /// Bounding rectangles of [selectedText] in PDF page-space coordinates.
  /// Empty list when no bounds could be captured.
  final List<NoteRect> rectList;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-modified timestamp. Equal to [createdAt] until first edit.
  final DateTime updatedAt;

  // ---------------------------------------------------------------------------
  // Convenience factories
  // ---------------------------------------------------------------------------

  factory Note.create({
    required String pdfId,
    required int page,
    required String noteText,
    String selectedText = '',
    List<NoteRect> rectList = const [],
  }) {
    final now = DateTime.now().toUtc();
    return Note(
      pdfId:        pdfId,
      page:         page,
      noteText:     noteText,
      selectedText: selectedText,
      rectList:     rectList,
      createdAt:    now,
      updatedAt:    now,
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Note copyWith({
    int?           id,
    String?        pdfId,
    int?           page,
    String?        noteText,
    String?        selectedText,
    List<NoteRect>? rectList,
    DateTime?      createdAt,
    DateTime?      updatedAt,
  }) {
    return Note(
      id:           id           ?? this.id,
      pdfId:        pdfId        ?? this.pdfId,
      page:         page         ?? this.page,
      noteText:     noteText     ?? this.noteText,
      selectedText: selectedText ?? this.selectedText,
      rectList:     rectList     ?? this.rectList,
      createdAt:    createdAt    ?? this.createdAt,
      updatedAt:    updatedAt    ?? this.updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId:            pdfId,
      DatabaseConstants.columnPage:             page,
      DatabaseConstants.columnNoteText:         noteText,
      DatabaseConstants.columnNoteSelectedText: selectedText,
      DatabaseConstants.columnNoteRectList:     _encodeRects(rectList),
      DatabaseConstants.columnCreatedAt:        createdAt.toUtc().toIso8601String(),
      DatabaseConstants.columnUpdatedAt:        updatedAt.toUtc().toIso8601String(),
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    try {
      final rectRaw = (map[DatabaseConstants.columnNoteRectList] as String?) ?? '';
      return Note(
        id:           map[DatabaseConstants.columnId]   as int?,
        pdfId:        map[DatabaseConstants.columnPdfId] as String,
        page:         map[DatabaseConstants.columnPage]  as int,
        noteText:     map[DatabaseConstants.columnNoteText] as String,
        selectedText: (map[DatabaseConstants.columnNoteSelectedText] as String?) ?? '',
        rectList:     rectRaw.isEmpty ? const [] : _decodeRects(rectRaw),
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
  // Codec helpers
  // ---------------------------------------------------------------------------

  static String _encodeRects(List<NoteRect> rects) =>
      rects.map((r) => r.encode()).join('|');

  static List<NoteRect> _decodeRects(String encoded) =>
      encoded.split('|').map(NoteRect.fromString).toList();

  // ---------------------------------------------------------------------------
  // Equality & hashing
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Note) return false;
    return other.id           == id           &&
        other.pdfId        == pdfId        &&
        other.page         == page         &&
        other.noteText     == noteText     &&
        other.selectedText == selectedText &&
        other.createdAt    == createdAt    &&
        other.updatedAt    == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, pdfId, page, noteText, selectedText, createdAt, updatedAt);

  @override
  String toString() => 'Note('
      'id: $id, pdfId: $pdfId, page: $page, '
      'selectedText: "${selectedText.length > 30
      ? '${selectedText.substring(0, 30)}...'
      : selectedText}", '
      'noteText: "${noteText.length > 30
      ? '${noteText.substring(0, 30)}...'
      : noteText}", '
      'rects: ${rectList.length}, '
      'updatedAt: $updatedAt)';
}