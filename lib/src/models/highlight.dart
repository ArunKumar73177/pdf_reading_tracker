import '../constants/database_constants.dart';

// ---------------------------------------------------------------------------
// AnnotationType
// ---------------------------------------------------------------------------

/// The visual style of a text-markup annotation.
///
/// Maps 1-to-1 with Syncfusion's annotation classes:
/// - [highlight]      → `sf.HighlightAnnotation`
/// - [underline]      → `sf.UnderlineAnnotation`
/// - [strikethrough]  → `sf.StrikethroughAnnotation`
/// - [squiggly]       → `sf.SquigglyAnnotation`
///
/// Stored in SQLite as a plain string so the schema is human-readable and
/// forward-compatible (no integer codes to maintain).
enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  squiggly;

  /// Canonical string stored in the database.
  String get dbValue => name; // 'highlight', 'underline', etc.

  /// Parses a database string back to the enum.
  /// Defaults to [highlight] for any unrecognised value — ensures backward
  /// compatibility with pre-v6 rows that have no annotation_type column.
  static AnnotationType fromDbValue(String? value) {
    switch (value) {
      case 'underline':     return AnnotationType.underline;
      case 'strikethrough': return AnnotationType.strikethrough;
      case 'squiggly':      return AnnotationType.squiggly;
      default:              return AnnotationType.highlight;
    }
  }
}

// ---------------------------------------------------------------------------
// Default color palette
// ---------------------------------------------------------------------------

/// Predefined ARGB color constants for annotation UI.
///
/// Alpha is 60 % (0x99) for all colours so underlying text remains legible.
/// Values are raw ints — no Flutter dependency on this model file.
abstract final class AnnotationColors {
  AnnotationColors._();

  static const int yellow  = 0x99FFEB3B;
  static const int green   = 0x9966BB6A;
  static const int blue    = 0x9942A5F5;
  static const int pink    = 0x99EC407A;
  static const int orange  = 0x99FFA726;
  static const int purple  = 0x99AB47BC;

  /// Ordered list used by the color picker in [AnnotationActionBar].
  static const List<int> palette = [
    yellow, green, blue, pink, orange, purple,
  ];
}

// ---------------------------------------------------------------------------
// Highlight
// ---------------------------------------------------------------------------

/// Immutable value object representing a persisted text annotation on a PDF
/// page.
///
/// ### Page convention
/// [page] is **zero-based**. Syncfusion's annotation `pageNumber` is
/// **one-based**; conversion happens at the controller boundary.
///
/// ### Multi-rect bounds
/// A single user selection can span multiple text lines. Stored as a
/// pipe-separated string of `"left,top,right,bottom"` records.
///
/// ### Color
/// [colorValue] stores `Color.value` (ARGB int). Convert with
/// `Color(highlight.colorValue)` at the render layer.
///
/// ### Annotation type
/// [annotationType] records which Syncfusion annotation class to use on
/// restore. Defaults to [AnnotationType.highlight] for all pre-v6 rows.
class Highlight {
  const Highlight({
    this.id,
    required this.pdfId,
    required this.page,
    required this.selectedText,
    required this.rectList,
    required this.colorValue,
    required this.annotationType,
    required this.createdAt,
    this.note,
  }) : assert(page >= 0, 'page must be >= 0');

  /// Auto-incremented SQLite primary key. `null` before the first INSERT.
  final int? id;

  /// Stable PDF identifier.
  final String pdfId;

  /// Zero-based page index.
  final int page;

  /// Plain-text content of the annotated selection.
  final String selectedText;

  /// One or more bounding rectangles in PDF page-space coordinates.
  final List<HighlightRect> rectList;

  /// ARGB colour integer (`Color.value`).
  final int colorValue;

  /// Visual style of this annotation.
  final AnnotationType annotationType;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// Optional user note attached to this annotation.
  final String? note;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  factory Highlight.create({
    required String pdfId,
    required int page,
    required String selectedText,
    required List<HighlightRect> rectList,
    int colorValue = AnnotationColors.yellow,
    AnnotationType annotationType = AnnotationType.highlight,
    String? note,
  }) {
    return Highlight(
      pdfId:          pdfId,
      page:           page,
      selectedText:   selectedText,
      rectList:       rectList,
      colorValue:     colorValue,
      annotationType: annotationType,
      createdAt:      DateTime.now().toUtc(),
      note:           note,
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
    AnnotationType?      annotationType,
    DateTime?            createdAt,
    String?              note,
    bool                 clearNote = false,
  }) {
    return Highlight(
      id:             id             ?? this.id,
      pdfId:          pdfId          ?? this.pdfId,
      page:           page           ?? this.page,
      selectedText:   selectedText   ?? this.selectedText,
      rectList:       rectList       ?? this.rectList,
      colorValue:     colorValue     ?? this.colorValue,
      annotationType: annotationType ?? this.annotationType,
      createdAt:      createdAt      ?? this.createdAt,
      note:           clearNote ? null : (note ?? this.note),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId:          pdfId,
      DatabaseConstants.columnPage:           page,
      DatabaseConstants.columnSelectedText:   selectedText,
      DatabaseConstants.columnRectList:       _encodeRects(rectList),
      DatabaseConstants.columnColorValue:     colorValue,
      DatabaseConstants.columnAnnotationType: annotationType.dbValue,
      DatabaseConstants.columnCreatedAt:      createdAt.toUtc().toIso8601String(),
      DatabaseConstants.columnNote:           note,
    };
  }

  factory Highlight.fromMap(Map<String, dynamic> map) {
    try {
      return Highlight(
        id:   map[DatabaseConstants.columnId] as int?,
        pdfId: map[DatabaseConstants.columnPdfId] as String,
        page:  map[DatabaseConstants.columnPage]  as int,
        selectedText: map[DatabaseConstants.columnSelectedText] as String,
        rectList: _decodeRects(
            map[DatabaseConstants.columnRectList] as String),
        colorValue: map[DatabaseConstants.columnColorValue] as int,
        // Backward-compatible: pre-v6 rows have no annotation_type column.
        annotationType: AnnotationType.fromDbValue(
            map[DatabaseConstants.columnAnnotationType] as String?),
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        note: map[DatabaseConstants.columnNote] as String?,
      );
    } catch (e) {
      throw FormatException(
          'Highlight.fromMap failed. Cause: $e\nRow: $map');
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
    return other.id             == id             &&
        other.pdfId          == pdfId          &&
        other.page           == page           &&
        other.selectedText   == selectedText   &&
        other.colorValue     == colorValue     &&
        other.annotationType == annotationType &&
        other.createdAt      == createdAt      &&
        other.note           == note;
  }

  @override
  int get hashCode => Object.hash(
      id, pdfId, page, selectedText, colorValue, annotationType,
      createdAt, note);

  @override
  String toString() => 'Highlight('
      'id: $id, pdfId: $pdfId, page: $page, '
      'type: ${annotationType.dbValue}, '
      'rects: ${rectList.length}, '
      'color: 0x${colorValue.toRadixString(16).toUpperCase().padLeft(8, '0')}, '
      'text: "${selectedText.length > 30
      ? '${selectedText.substring(0, 30)}...'
      : selectedText}")';
}

// ---------------------------------------------------------------------------
// HighlightRect
// ---------------------------------------------------------------------------

/// A bounding rectangle in PDF page-space coordinates (origin top-left,
/// Y growing downward, unit: points).
///
/// Encoded as `"left,top,right,bottom"` for pipe-delimited SQLite storage.
/// A single annotation row can reference many rects — one per text line in
/// a multi-line selection.
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
    return other.left   == left  && other.top    == top &&
        other.right  == right && other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'HighlightRect(l:$left, t:$top, r:$right, b:$bottom)';
}