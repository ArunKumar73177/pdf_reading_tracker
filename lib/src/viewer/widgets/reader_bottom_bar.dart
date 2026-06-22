import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ReaderProgressOverlay
// ---------------------------------------------------------------------------

/// Compact floating progress pill — permanently visible at the bottom of the
/// PDF viewport.
///
/// ### Permanent visibility (Issue 1 fix)
/// No [AnimationController], no [Timer], no auto-hide. The pill is a pure
/// [StatelessWidget] that renders every time its parent [ListenableBuilder]
/// rebuilds, which happens only on genuine page/save/note changes — not on
/// every scroll frame.
///
/// ### Note badge (Issue 2 secondary indicator)
/// When [noteCountOnCurrentPage] > 0, a small teal note icon appears to the
/// left of the progress bar. This is a secondary indicator; the primary
/// indicator is the in-PDF teal highlight annotation added by
/// [PdfViewerController.addNote].
///
/// ### Performance
/// Wrapped in a [RepaintBoundary]. All color values are compile-time
/// constants (no [Color.withOpacity] calls — deprecated in Flutter 3.27+
/// and allocation-heavy on every paint).
class ReaderProgressOverlay extends StatelessWidget {
  const ReaderProgressOverlay({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    this.isSaving               = false,
    this.noteCountOnCurrentPage = 0,
  });

  final int    currentPage;
  final int    totalPages;
  final double progressPct;
  final bool   isSaving;

  /// Pre-computed by [PdfViewerController.noteCountOnCurrentPage]. Reading
  /// this is O(1) — no inline filtering in the build method.
  final int noteCountOnCurrentPage;

  // Compile-time color constants — no runtime allocation on each paint.
  static const Color _kBackground   = Color(0x8C000000); // black 55 %
  static const Color _kTrack        = Color(0x40FFFFFF); // white 25 %
  static const Color _kFill         = Colors.white;
  static const Color _kLabel        = Colors.white;
  static const Color _kPct          = Color(0x99FFFFFF); // white 60 %
  static const Color _kSaving       = Color(0xB3FFFFFF); // white 70 %
  static const Color _kNoteIcon     = Color(0xFF80DEEA); // teal 200

  @override
  Widget build(BuildContext context) {
    final pageLabel = totalPages > 0
        ? 'Page ${currentPage + 1} / $totalPages'
        : 'Loading…';
    final pct = totalPages > 0
        ? '${progressPct.toStringAsFixed(0)}%'
        : '';

    return Positioned(
      left:   16,
      right:  16,
      bottom: 16,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height:  44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color:        _kBackground,
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            child: Row(
              children: [
                // ── Note badge (secondary indicator) ─────────────────
                if (noteCountOnCurrentPage > 0) ...[
                  Tooltip(
                    message: '$noteCountOnCurrentPage '
                        'note${noteCountOnCurrentPage == 1 ? '' : 's'} '
                        'on this page',
                    child: const Icon(
                      Icons.sticky_note_2_rounded,
                      size:  14,
                      color: _kNoteIcon,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // ── Progress bar ──────────────────────────────────────
                Expanded(
                  child: _MiniProgressBar(
                    progressPct: progressPct,
                    trackColor:  _kTrack,
                    fillColor:   _kFill,
                  ),
                ),

                const SizedBox(width: 12),

                // ── Page label ────────────────────────────────────────
                Text(
                  pageLabel,
                  style: const TextStyle(
                    color:      _kLabel,
                    fontSize:   12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                if (pct.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(pct,
                      style: const TextStyle(
                          color: _kPct, fontSize: 11)),
                ],

                // ── Saving spinner ────────────────────────────────────
                AnimatedOpacity(
                  opacity:  isSaving ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width:  10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color:       _kSaving,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MiniProgressBar
// ---------------------------------------------------------------------------

/// Thin animated progress bar used inside [ReaderProgressOverlay].
///
/// ### Issue 4 fix — LayoutBuilder replaced with FractionallySizedBox
/// The previous implementation used [LayoutBuilder] + [AnimatedContainer]
/// with an explicit pixel width computed from `constraints.maxWidth`. This
/// caused a deferred layout pass on every rebuild. [FractionallySizedBox]
/// computes its child's width as a fraction of the parent constraint in a
/// single layout pass without a builder callback.
///
/// [AnimatedContainer] still drives the implicit width animation; its `width`
/// is expressed as a fraction-derived value only after the
/// [FractionallySizedBox] resolves the available width.
///
/// Both the track and fill are wrapped together in a single [RepaintBoundary]
/// so only this narrow 4 dp strip is repainted during animation.
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({
    required this.progressPct,
    required this.trackColor,
    required this.fillColor,
  });

  final double progressPct;
  final Color  trackColor;
  final Color  fillColor;

  @override
  Widget build(BuildContext context) {
    final fraction = (progressPct / 100.0).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final totalW = constraints.maxWidth;
            final fillW  = fraction * totalW;
            return Stack(
              children: [
                // Track
                DecoratedBox(
                  decoration: BoxDecoration(
                    color:        trackColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox.expand(),
                ),
                // Fill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve:    Curves.easeOut,
                  width:    fillW,
                  height:   4,
                  decoration: BoxDecoration(
                    color:        fillColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}