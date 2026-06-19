import '../constants/database_constants.dart';

/// Immutable value object representing a persisted text highlight on a PDF page.
///
/// ### Page convention
/// [page] is **zero-based**, consistent with [Bookmark] and [ReadingProgress].
/// Syncfusion's `HighlightAnnotation.pageNumber` is **one-based**; the
/// conversion happens at the boundary in [PdfViewerController].
///
/// ### Multi-rect bounds
/// A single user selection can span multiple text lines. Syncfusion represents
/// this as `List<Rect> textMarkupRects`. We persist this as a
/// pipe-separated string of `"left,top,right,bottom"` records so it round-trips
/// cleanly through SQLite TEXT without requiring a child table.
///
/// ### Color
/// [colorValue] stores `Color.value` (ARGB int) so the model has no Flutter
/// dependency. Convert with `Color(highlight.colorValue)` at the render layer.
class Highlight {
  const Highlight({
    this.id,
    required this.pdfId,
    required this.page,
    required this.selectedText,
    required this.rectList,
    required this.colorValue,
    required this.createdAt,
    this.note,
  })  : assert(page >= 0, 'page must be >= 0');

  /// Auto-incremented SQLite primary key. `null` before the first INSERT.
  final int? id;

  /// Stable PDF identifier (same as [ReadingProgress.pdfId]).
  final String pdfId;

  /// Zero-based page index.
  final int page;

  /// Plain-text content of the highlighted selection.
  final String selectedText;

  /// One or more bounding rectangles in PDF page-space coordinates.
  ///
  /// PDF page-space has origin at top-left, Y growing downward, in points.
  /// Syncfusion's `PdfTextLine.bounds` and `HighlightAnnotation.textMarkupRects`
  /// use this same coordinate system.
  final List<HighlightRect> rectList;

  /// ARGB colour integer (`Color.value`). Default: 60% yellow = `0x99FFEB3B`.
  final int colorValue;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// Optional user annotation.
  final String? note;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  factory Highlight.create({
    required String pdfId,
    required int page,
    required String selectedText,
    required List<HighlightRect> rectList,
    int colorValue = 0x99FFEB3B,
    String? note,
  }) {
    return Highlight(
      pdfId:        pdfId,
      page:         page,
      selectedText: selectedText,
      rectList:     rectList,
      colorValue:   colorValue,
      createdAt:    DateTime.now().toUtc(),
      note:         note,
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Highlight copyWith({
    int?                 id,
    String?              pdfId,
    int?                 page,
    String?              selectedText,
    List<HighlightRect>? rectList,
    int?                 colorValue,
    DateTime?            createdAt,
    String?              note,
    bool                 clearNote = false,
  }) {
    return Highlight(
      id:           id           ?? this.id,
      pdfId:        pdfId        ?? this.pdfId,
      page:         page         ?? this.page,
      selectedText: selectedText ?? this.selectedText,
      rectList:     rectList     ?? this.rectList,
      colorValue:   colorValue   ?? this.colorValue,
      createdAt:    createdAt    ?? this.createdAt,
      note:         clearNote ? null : (note ?? this.note),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId:        pdfId,
      DatabaseConstants.columnPage:         page,
      DatabaseConstants.columnSelectedText: selectedText,
      DatabaseConstants.columnRectList:     _encodeRects(rectList),
      DatabaseConstants.columnColorValue:   colorValue,
      DatabaseConstants.columnCreatedAt:    createdAt.toUtc().toIso8601String(),
      DatabaseConstants.columnNote:         note,
    };
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    try {
      return Highlight(
        id:           map[DatabaseConstants.columnId]           as int?,
        pdfId:        map[DatabaseConstants.columnPdfId]        as String,
        page:         map[DatabaseConstants.columnPage]         as int,
        selectedText: map[DatabaseConstants.columnSelectedText] as String,
        rectList:     _decodeRects(
            map[DatabaseConstants.columnRectList] as String),
        colorValue:   map[DatabaseConstants.columnColorValue]   as int,
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        note: map[DatabaseConstants.columnNote] as String?,
      );
    } catch (e) {
      throw FormatException('Highlight.fromMap failed. Cause: $e\nRow: $map');
    }
  }

  // ---------------------------------------------------------------------------
  // Codec helpers
  // ---------------------------------------------------------------------------

  static String _encodeRects(List<HighlightRect> rects) =>
      rects.map((r) => r.encode()).join('|');

  static List<HighlightRect> _decodeRects(String encoded) =>
      encoded.split('|').map(HighlightRect.fromString).toList();

  // ---------------------------------------------------------------------------
  // Equality & hashing
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Highlight) return false;
    return other.id           == id           &&
        other.pdfId        == pdfId        &&
        other.page         == page         &&
        other.selectedText == selectedText &&
        other.colorValue   == colorValue   &&
        other.createdAt    == createdAt    &&
        other.note         == note;
  }

  @override
  int get hashCode =>
      Object.hash(id, pdfId, page, selectedText, colorValue, createdAt, note);

  @override
  String toString() => 'Highlight('
      'id: $id, pdfId: $pdfId, page: $page, '
      'rects: ${rectList.length}, '
      'color: 0x${colorValue.toRadixString(16).toUpperCase().padLeft(8, '0')}, '
      'text: "${selectedText.length > 30
      ? '${selectedText.substring(0, 30)}...'
      : selectedText}")';
}

// ---------------------------------------------------------------------------
// HighlightRect — a single PDF page-space bounding rectangle
// ---------------------------------------------------------------------------

/// A bounding rectangle in PDF page-space coordinates (origin top-left, points).
///
/// Encoded as `"left,top,right,bottom"` for pipe-delimited SQLite storage.
class HighlightRect {
  const HighlightRect({
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

  factory HighlightRect.fromString(String s) {
    final p = s.split(',');
    if (p.length != 4) {
      throw FormatException(
          'HighlightRect.fromString: expected 4 values, got "$s"');
    }
    return HighlightRect(
      left:   double.parse(p[0]),
      top:    double.parse(p[1]),
      right:  double.parse(p[2]),
      bottom: double.parse(p[3]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HighlightRect) return false;
    return other.left == left && other.top == top &&
        other.right == right && other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'HighlightRect(l:$left, t:$top, r:$right, b:$bottom)';
}