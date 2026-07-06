import '../constants/database_constants.dart';

/// Immutable value object representing a user's reading progress for a single
/// PDF document.
///
/// **v2.1.1 fix — progress percentage**
/// `progressPct` is now computed as `(currentPage + 1) / totalPages * 100`.
/// Previously it used `currentPage / totalPages`, causing:
///   - Page 1  (index 0) → 0 %   (Bug 3)
///   - Last page (index N-1) → (N-1)/N*100, never 100 % (Bug 2)
///
/// The corrected formula:
///   - Page 1  (index 0) → 1/N * 100  (user has started reading)
///   - Last page (index N-1) → N/N * 100 = 100 %
///
/// [filePath] is `null` for asset-backed PDFs bundled with the app and
/// non-null for PDFs the user picked from their device via [PdfPickerService].
class ReadingProgress {
  const ReadingProgress({
    this.id,
    required this.pdfId,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    required this.lastReadAt,
    required this.createdAt,
    this.title,
    this.filePath,
  })  : assert(currentPage >= 0, 'currentPage must be >= 0'),
        assert(totalPages >= 0, 'totalPages must be >= 0'),
        assert(currentPage <= totalPages, 'currentPage must be <= totalPages'),
        assert(
          progressPct >= 0.0 && progressPct <= 100.0,
          'progressPct must be in [0.0, 100.0]',
        );

  final int? id;

  /// Unique, stable identifier for the PDF (file path hash for user PDFs,
  /// asset key for bundled PDFs).
  final String pdfId;

  /// Zero-based index of the currently displayed page.
  final int currentPage;

  final int totalPages;

  /// Read-completion percentage in [0.0, 100.0].
  ///
  /// Computed as `((currentPage + 1) / totalPages * 100).clamp(0.0, 100.0)`
  /// so that page-index 0 (first page) yields >0 % and the last page always
  /// yields exactly 100 %.
  final double progressPct;

  final DateTime lastReadAt;
  final DateTime createdAt;

  /// Human-readable title shown in the UI (filename or document title).
  final String? title;

  /// Absolute on-device file path for user-picked PDFs; `null` for assets.
  ///
  /// Always points to the **persistent** copy inside
  /// `ApplicationDocumentsDirectory/user_pdfs/` — never a temp/cache path.
  ///
  /// Use this to verify the file still exists before opening:
  /// ```dart
  /// if (progress.filePath != null && !File(progress.filePath!).existsSync()) {
  ///   // file was deleted / moved
  /// }
  /// ```
  final String? filePath;

  // ---------------------------------------------------------------------------
  // Convenience factories
  // ---------------------------------------------------------------------------

  factory ReadingProgress.create({
    required String pdfId,
    required int currentPage,
    required int totalPages,
    String? title,
    String? filePath,
  }) {
    final now = DateTime.now().toUtc();
    final pct = _computeProgressPct(currentPage, totalPages);
    return ReadingProgress(
      pdfId: pdfId,
      currentPage: currentPage,
      totalPages: totalPages,
      progressPct: pct,
      lastReadAt: now,
      createdAt: now,
      title: title,
      filePath: filePath,
    );
  }

  // ---------------------------------------------------------------------------
  // Progress percentage helper
  // ---------------------------------------------------------------------------

  /// Computes `progressPct` from zero-based [page] and [total].
  ///
  /// - total == 0  → 0.0  (PDF not yet rendered)
  /// - page == 0   → 1/total * 100  (first page viewed, not zero)
  /// - page == total-1 → 100.0  (last page)
  static double _computeProgressPct(int page, int total) {
    if (total <= 0) return 0.0;
    return ((page + 1) / total * 100.0).clamp(0.0, 100.0);
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
    String? filePath,
    bool clearFilePath = false,
  }) {
    final resolvedPage = currentPage ?? this.currentPage;
    final resolvedTotal = totalPages ?? this.totalPages;
    // Recompute progressPct from updated page/total unless caller provides it.
    final resolvedPct =
        progressPct ?? _computeProgressPct(resolvedPage, resolvedTotal);

    return ReadingProgress(
      id: id ?? this.id,
      pdfId: pdfId ?? this.pdfId,
      currentPage: resolvedPage,
      totalPages: resolvedTotal,
      progressPct: resolvedPct,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      title: clearTitle ? null : (title ?? this.title),
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation
  // ---------------------------------------------------------------------------

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
      DatabaseConstants.columnFilePath: filePath,
    };
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    try {
      return ReadingProgress(
        id: map[DatabaseConstants.columnId] as int?,
        pdfId: map[DatabaseConstants.columnPdfId] as String,
        currentPage: map[DatabaseConstants.columnCurrentPage] as int,
        totalPages: map[DatabaseConstants.columnTotalPages] as int,
        progressPct:
            (map[DatabaseConstants.columnProgressPct] as num).toDouble(),
        lastReadAt: DateTime.parse(
          map[DatabaseConstants.columnLastReadAt] as String,
        ).toLocal(),
        createdAt: DateTime.parse(
          map[DatabaseConstants.columnCreatedAt] as String,
        ).toLocal(),
        title: map[DatabaseConstants.columnTitle] as String?,
        filePath: map[DatabaseConstants.columnFilePath] as String?,
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
        other.title == title &&
        other.filePath == filePath;
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
        filePath,
      );

  @override
  String toString() => 'ReadingProgress('
      'id: $id, pdfId: $pdfId, title: $title, filePath: $filePath, '
      'currentPage: $currentPage, totalPages: $totalPages, '
      'progressPct: ${progressPct.toStringAsFixed(2)}%, '
      'lastReadAt: $lastReadAt, createdAt: $createdAt)';
}
