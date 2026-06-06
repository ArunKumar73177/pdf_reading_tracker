import '../constants/database_constants.dart';

/// Immutable value object representing a user's reading progress for a single
/// PDF document.
///
/// Persisted to and restored from SQLite via [toMap] / [fromMap].
class ReadingProgress {
  /// Auto-incremented primary key. `null` before the record is first inserted.
  final int? id;

  /// Unique, stable identifier for the PDF (e.g. file path, asset key, or UUID).
  final String pdfId;

  /// Zero-based index of the last page the user was on.
  final int currentPage;

  /// Total number of pages in the document.
  final int totalPages;

  /// Read-completion percentage in the range [0.0, 100.0].
  ///
  /// Computed on write by the service layer; stored for fast querying without
  /// recalculation.
  final double progressPct;

  /// Timestamp of the most recent read event.
  final DateTime lastReadAt;

  /// Timestamp when this progress record was first created.
  final DateTime createdAt;

  /// Optional human-readable title of the PDF (e.g. filename or document title).
  final String? title;

  const ReadingProgress({
    this.id,
    required this.pdfId,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    required this.lastReadAt,
    required this.createdAt,
    this.title,
  })  : assert(currentPage >= 0, 'currentPage must be ≥ 0'),
        assert(totalPages >= 0, 'totalPages must be ≥ 0'),
        assert(
        currentPage <= totalPages,
        'currentPage must be ≤ totalPages',
        ),
        assert(
        progressPct >= 0.0 && progressPct <= 100.0,
        'progressPct must be in [0.0, 100.0]',
        );

  // ---------------------------------------------------------------------------
  // Convenience factory
  // ---------------------------------------------------------------------------

  /// Creates a brand-new [ReadingProgress] with [createdAt] and [lastReadAt]
  /// both set to [DateTime.now] and [progressPct] computed automatically.
  factory ReadingProgress.create({
    required String pdfId,
    required int currentPage,
    required int totalPages,
    String? title,
  }) {
    final now = DateTime.now().toUtc();
    final pct = totalPages > 0
        ? ((currentPage / totalPages) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    return ReadingProgress(
      pdfId: pdfId,
      currentPage: currentPage,
      totalPages: totalPages,
      progressPct: pct,
      lastReadAt: now,
      createdAt: now,
      title: title,
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  ReadingProgress copyWith({
    int? id,
    String? pdfId,
    int? currentPage,
    int? totalPages,
    double? progressPct,
    DateTime? lastReadAt,
    DateTime? createdAt,
    String? title,
    bool clearTitle = false,
  }) {
    return ReadingProgress(
      id: id ?? this.id,
      pdfId: pdfId ?? this.pdfId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      progressPct: progressPct ?? this.progressPct,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      title: clearTitle ? null : (title ?? this.title),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

  /// Converts this instance to a column→value map suitable for sqflite.
  ///
  /// [id] is excluded when `null` so that sqflite auto-increments on INSERT.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) DatabaseConstants.columnId: id,
      DatabaseConstants.columnPdfId: pdfId,
      DatabaseConstants.columnCurrentPage: currentPage,
      DatabaseConstants.columnTotalPages: totalPages,
      DatabaseConstants.columnProgressPct: progressPct,
      DatabaseConstants.columnLastReadAt: lastReadAt.toUtc().toIso8601String(),
      DatabaseConstants.columnCreatedAt: createdAt.toUtc().toIso8601String(),
      DatabaseConstants.columnTitle: title,
    };
  }

  /// Deserialises a sqflite row map into a [ReadingProgress].
  ///
  /// Throws a [FormatException] if any required field is missing or has an
  /// unexpected type, so callers surface schema mismatches early.
  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    try {
      return ReadingProgress(
        id: map[DatabaseConstants.columnId] as int?,
        pdfId: map[DatabaseConstants.columnPdfId] as String,
        currentPage: map[DatabaseConstants.columnCurrentPage] as int,
        totalPages: map[DatabaseConstants.columnTotalPages] as int,
        progressPct: (map[DatabaseConstants.columnProgressPct] as num).toDouble(),
        lastReadAt: DateTime.parse(
          map[DatabaseConstants.columnLastReadAt] as String,
        ).toLocal(),
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        title: map[DatabaseConstants.columnTitle] as String?,
      );
    } catch (e) {
      throw FormatException(
        'ReadingProgress.fromMap failed — check column names and types. '
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
    if (other is! ReadingProgress) return false;

    return other.id == id &&
        other.pdfId == pdfId &&
        other.currentPage == currentPage &&
        other.totalPages == totalPages &&
        other.progressPct == progressPct &&
        other.lastReadAt == lastReadAt &&
        other.createdAt == createdAt &&
        other.title == title;
  }

  @override
  int get hashCode => Object.hash(
    id,
    pdfId,
    currentPage,
    totalPages,
    progressPct,
    lastReadAt,
    createdAt,
    title,
  );

  // ---------------------------------------------------------------------------
  // Debugging
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    return 'ReadingProgress('
        'id: $id, '
        'pdfId: $pdfId, '
        'title: $title, '
        'currentPage: $currentPage, '
        'totalPages: $totalPages, '
        'progressPct: ${progressPct.toStringAsFixed(2)}%, '
        'lastReadAt: $lastReadAt, '
        'createdAt: $createdAt'
        ')';
  }
}