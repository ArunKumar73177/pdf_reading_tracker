import 'dart:math' as math;
import 'dart:ui' show Size;

// ---------------------------------------------------------------------------
// PageGeometryEngine
// ---------------------------------------------------------------------------

/// Immutable, precomputed page-geometry lookup table.
///
/// Built exactly once per document load (and, rarely, once more on a
/// genuine viewport cross-axis size change such as device rotation or
/// window resize) via [PageGeometryEngine.build]. **Never** recalculated
/// on a per-scroll-frame basis — [dominantPage] only ever reads this
/// cached table.
///
/// ### Units
/// Internally the table stores *normalized* cumulative offsets (fraction
/// of total scrollable content extent, in `[0, 1]`) rather than absolute
/// pixels. Absolute pixel offsets are derived at query time by scaling
/// against the live `maxScrollExtent + viewportDimension`. Because zoom
/// scales every page and every gap by the same factor, the *ratios*
/// between pages stay constant across zoom levels — a table built at
/// zoom 1.0 remains correct at any zoom level without rebuilding.
///
/// ### Page spacing
/// Syncfusion's continuous layout mode inserts a fixed pixel gap
/// (`pageSpacing`) between consecutive pages. That gap is folded into
/// each page's weight as a proportional fraction of the viewport's
/// cross-axis extent (the axis pages are *not* scrolling along — width
/// for vertical scroll, height for horizontal scroll — since that's the
/// axis pages are scaled to fit). Ignoring it would under-count total
/// content extent by `(pageCount - 1) * pageSpacing` pixels, which is
/// significant for large page counts.
///
/// ### Scroll-axis awareness
/// - Vertical continuous mode: pages are scaled to fit viewport *width*;
///   each page's along-scroll extent is proportional to `height / width`.
/// - Horizontal continuous mode: pages are scaled to fit viewport
///   *height*; each page's along-scroll extent is proportional to
///   `width / height`.
class PageGeometryEngine {
  PageGeometryEngine._(
      this._normalizedOffsets,
      this.pageCount,
      this.builtForCrossAxisExtent,
      );

  /// Length == pageCount + 1. `_normalizedOffsets[i]` = fraction of total
  /// scrollable content extent above page `i` (monotonically increasing,
  /// `_normalizedOffsets[0] == 0.0`, `_normalizedOffsets[pageCount] == 1.0`).
  final List<double> _normalizedOffsets;

  final int pageCount;

  /// The viewport cross-axis extent (width for vertical scroll, height
  /// for horizontal scroll) this table was built against. Used by
  /// [isStaleFor] to detect when a rebuild is warranted.
  final double builtForCrossAxisExtent;

  /// Builds the lookup table in O(n). Intended to be called once per
  /// document load, plus rarely again on a genuine cross-axis viewport
  /// size change.
  ///
  /// [pageSizesPts] — each page's (width, height) in PDF points, in
  /// document order. Read directly from the already-loaded
  /// `PdfDocument` — this performs no additional PDF parsing.
  ///
  /// [pageSpacingPx] — the fixed pixel gap Syncfusion renders between
  /// consecutive pages (0 for horizontal/paginated layouts).
  ///
  /// [viewportCrossAxisPx] — the viewport's extent along the axis pages
  /// are scaled to fit (width for vertical scroll, height for
  /// horizontal scroll).
  ///
  /// [isHorizontalScroll] — selects which page dimension varies along
  /// the scroll axis.
  factory PageGeometryEngine.build(
      List<Size> pageSizesPts, {
        required double pageSpacingPx,
        required double viewportCrossAxisPx,
        required bool isHorizontalScroll,
      }) {
    final n = pageSizesPts.length;
    if (n == 0) {
      return PageGeometryEngine._(<double>[0.0], 0, viewportCrossAxisPx);
    }

    final safeCrossAxis = viewportCrossAxisPx > 0 ? viewportCrossAxisPx : 1.0;
    final gapWeight = pageSpacingPx > 0 ? pageSpacingPx / safeCrossAxis : 0.0;

    final weights = List<double>.filled(n, 1.0);
    for (var i = 0; i < n; i++) {
      final w = pageSizesPts[i].width;
      final h = pageSizesPts[i].height;
      double alongAxis;
      if (w > 0 && h > 0) {
        // Vertical scroll: page scaled to fit width -> along-axis extent
        // (height) is proportional to height/width.
        // Horizontal scroll: page scaled to fit height -> along-axis
        // extent (width) is proportional to width/height.
        alongAxis = isHorizontalScroll ? (w / h) : (h / w);
      } else {
        // Degenerate page size reported — never let one bad value
        // corrupt the whole table; fall back to a square-page weight.
        alongAxis = 1.0;
      }
      // Trailing gap only between pages, not after the last page.
      weights[i] = alongAxis + (i < n - 1 ? gapWeight : 0.0);
    }

    final cum = List<double>.filled(n + 1, 0.0);
    for (var i = 0; i < n; i++) {
      cum[i + 1] = cum[i] + weights[i];
    }
    final total = cum[n] <= 0 ? 1.0 : cum[n];
    for (var i = 0; i <= n; i++) {
      cum[i] = cum[i] / total;
    }
    return PageGeometryEngine._(cum, n, viewportCrossAxisPx);
  }

  /// True if [currentCrossAxisExtent] has drifted enough from the extent
  /// this table was built against to warrant a rebuild (device rotation,
  /// window resize, split-screen change). A 1.0px tolerance avoids
  /// rebuilding on sub-pixel layout noise.
  bool isStaleFor(double currentCrossAxisExtent) {
    return (currentCrossAxisExtent - builtForCrossAxisExtent).abs() > 1.0;
  }

  /// Returns the zero-based page occupying the largest visible extent
  /// within `[scrollPixels, scrollPixels + viewportExtent]`.
  ///
  /// Not limited to any fixed number of simultaneously-visible pages —
  /// on large viewports (tablets, desktop, wide windows) where many pages
  /// may be visible at once, the local scan below naturally spans
  /// however many pages intersect the viewport.
  ///
  /// Complexity: O(log n) binary search + O(k) local scan, where k is the
  /// number of pages actually touching the viewport. No allocation.
  int dominantPage({
    required double scrollPixels,
    required double viewportExtent,
    required double totalContentExtent,
  }) {
    if (pageCount <= 0) return 0;
    if (pageCount == 1) return 0;
    if (totalContentExtent <= 0) return 0;

    final normTop = (scrollPixels / totalContentExtent).clamp(0.0, 1.0);
    final normBottom =
    ((scrollPixels + viewportExtent) / totalContentExtent).clamp(0.0, 1.0);

    var lo = _upperBound(normTop) - 1;
    if (lo < 0) lo = 0;
    var hi = _upperBound(normBottom);
    if (hi > pageCount) hi = pageCount;
    if (hi <= lo) hi = lo + 1;

    var bestPage = lo;
    var bestOverlap = -1.0;
    for (var p = lo; p < hi && p < pageCount; p++) {
      final pageStart = _normalizedOffsets[p];
      final pageEnd = _normalizedOffsets[p + 1];
      final overlapStart = math.max(pageStart, normTop);
      final overlapEnd = math.min(pageEnd, normBottom);
      final overlap = overlapEnd - overlapStart;
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestPage = p;
      }
    }
    return bestPage.clamp(0, pageCount - 1);
  }

  /// Standard upper-bound binary search: first index whose stored value
  /// is strictly greater than [value].
  int _upperBound(double value) {
    var lo = 0, hi = _normalizedOffsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_normalizedOffsets[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}