import '../constants/database_constants.dart';

/// Immutable value object representing a user-placed text highlight on a
/// specific page of a PDF document.
///
/// ### Page convention
/// [page] is **zero-based**, consistent with [Bookmark.page] and
/// [ReadingProgress.currentPage].
///
/// ### Geometry
/// [bounds] stores the bounding rectangle of the highlighted text in **PDF
/// user-space coordinates** (origin at bottom-left, Y grows upward).  These
/// are the coordinates reported by Syncfusion's
/// `PdfTextSelectionChangedDetails.globalSelectedText` or extracted from the
/// PDF document model.  Using PDF-space coordinates ensures the highlight
/// can be redrawn at the correct position regardless of the current zoom
/// level or scroll offset.
///
/// ### Colour
/// [colorValue] stores the ARGB integer (`Color.value`) so highlights can
/// be persisted without importing Flutter's `dart:ui` in the model layer.
/// Convert with `Color(highlight.colorValue)` when rendering.
///
/// Default colour is a semi-transparent yellow (0xFFFFEB3B at 60% opacity →
/// `0x99FFEB3B`).
class Highlight {
  const Highlight({
    this.id,
    required this.pdfId,
    required this.page,
    required this.selectedText,
    required this.bounds,
    required this.colorValue,
    required this.createdAt,
    this.note,
  }) : assert(page >= 0, 'page must be ≥ 0');

  /// Auto-incremented primary key.  `null` before the first INSERT.
  final int? id;

  /// Identifier of the PDF document this highlight belongs to.
  final String pdfId;

  /// Zero-based page index where the highlight appears.
  final int page;

  /// The plain-text content of the highlighted selection.
  final String selectedText;

  /// Bounding rectangle in PDF user-space coordinates.
  ///
  /// Encoded as `"left,top,right,bottom"` for SQLite storage and decoded
  /// with [HighlightBounds.fromString].
  final HighlightBounds bounds;

  /// ARGB colour integer (`Color.value`).
  final int colorValue;

  /// UTC timestamp when this highlight was created.
  final DateTime createdAt;

  /// Optional user annotation attached to the highlight.
  final String? note;

  // ---------------------------------------------------------------------------
  // Convenience factories
  // ---------------------------------------------------------------------------

  /// Creates a new [Highlight] with [createdAt] set to `DateTime.now` (UTC).
  factory Highlight.create({
    required String         pdfId,
    required int            page,
    required String         selectedText,
    required HighlightBounds bounds,
    int                     colorValue = _kDefaultHighlightColor,
    String?                 note,
  }) {
    return Highlight(
      pdfId:        pdfId,
      page:         page,
      selectedText: selectedText,
      bounds:       bounds,
      colorValue:   colorValue,
      createdAt:    DateTime.now().toUtc(),
      note:         note,
    );
  }

  static const int _kDefaultHighlightColor = 0x99FFEB3B; // 60% yellow

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Highlight copyWith({
    int?             id,
    String?          pdfId,
    int?             page,
    String?          selectedText,
    HighlightBounds? bounds,
    int?             colorValue,
    DateTime?        createdAt,
    String?          note,
    bool             clearNote = false,
  }) {
    return Highlight(
      id:           id           ?? this.id,
      pdfId:        pdfId        ?? this.pdfId,
      page:         page         ?? this.page,
      selectedText: selectedText ?? this.selectedText,
      bounds:       bounds       ?? this.bounds,
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
      if (id != null) DatabaseConstants.columnId:           id,
      DatabaseConstants.columnPdfId:        pdfId,
      DatabaseConstants.columnPage:         page,
      DatabaseConstants.columnSelectedText: selectedText,
      DatabaseConstants.columnBounds:       bounds.encode(),
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
        bounds: HighlightBounds.fromString(
            map[DatabaseConstants.columnBounds] as String),
        colorValue: map[DatabaseConstants.columnColorValue] as int,
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        note: map[DatabaseConstants.columnNote] as String?,
      );
    } catch (e) {
      throw FormatException(
        'Highlight.fromMap failed. Cause: $e\nRow: $map',
      );
    }
  }

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
        other.bounds       == bounds       &&
        other.colorValue   == colorValue   &&
        other.createdAt    == createdAt    &&
        other.note         == note;
  }

  @override
  int get hashCode => Object.hash(
      id, pdfId, page, selectedText, bounds, colorValue, createdAt, note);

  @override
  String toString() => 'Highlight('
      'id: $id, pdfId: $pdfId, page: $page, '
      'text: "${selectedText.length > 40
      ? '${selectedText.substring(0, 40)}…'
      : selectedText}", '
      'colorValue: 0x${colorValue.toRadixString(16).toUpperCase()}, '
      'createdAt: $createdAt)';
}

// ---------------------------------------------------------------------------
// HighlightBounds — PDF user-space rectangle
// ---------------------------------------------------------------------------

/// Bounding rectangle in PDF user-space coordinates.
///
/// Encoded as `"left,top,right,bottom"` for SQLite TEXT storage.
class HighlightBounds {
  const HighlightBounds({
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

  /// Encodes this rectangle as `"left,top,right,bottom"`.
  String encode() => '$left,$top,$right,$bottom';

  /// Decodes a string produced by [encode].
  factory HighlightBounds.fromString(String encoded) {
    final parts = encoded.split(',');
    if (parts.length != 4) {
      throw FormatException(
          'HighlightBounds.fromString: expected 4 comma-separated values, '
              'got "${encoded}"');
    }
    return HighlightBounds(
      left:   double.parse(parts[0]),
      top:    double.parse(parts[1]),
      right:  double.parse(parts[2]),
      bottom: double.parse(parts[3]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HighlightBounds) return false;
    return other.left   == left   &&
        other.top    == top    &&
        other.right  == right  &&
        other.bottom == bottom;
  }

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'HighlightBounds(left: $left, top: $top, right: $right, bottom: $bottom)';
}