import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';

// ---------------------------------------------------------------------------
// ReaderProgressOverlay
// ---------------------------------------------------------------------------

/// Compact floating progress pill shown at the bottom of the PDF viewport.
///
/// ### Auto-hide behaviour (Phase 2)
/// The pill fades in on genuine page changes (page turns, search jumps,
/// bookmark navigation, continue-reading restore, manual jump-to-page) and
/// fades out automatically after ~2 seconds of inactivity. It never stays
/// permanently visible and never rebuilds [SfPdfViewer] — this widget is
/// driven purely by the same [ListenableBuilder] the parent already uses
/// for `pageNotifier` / `savingNotifier` / `notesNotifier`.
///
/// ### Debounced visibility (rapid-scroll fix)
/// A naive implementation would cancel and recreate a [Timer] on every
/// single page-change notification, which during a fast fling through a
/// continuous-mode document can fire many times per second — churning
/// through many short-lived [Timer] allocations for no visible benefit
/// (opacity never actually changes mid-fling since the pill is already
/// visible). Instead, a single long-lived [Timer.periodic] "watchdog" is
/// created once per visibility cycle and simply checks elapsed time since
/// the last page change; it is cancelled only once the reader has actually
/// gone idle for the hide duration. This keeps rapid scrolling free of
/// [Timer] churn while still hiding reliably ~2 seconds after the user
/// stops turning pages.
///
/// ### Note badge (secondary indicator)
/// When [noteCountOnCurrentPage] > 0, a small note icon appears to the
/// left of the progress bar. This is a secondary indicator; the primary
/// indicator is the in-PDF highlight annotation added by
/// [PdfViewerController.addNote].
///
/// ### Progress display correctness (Phase 2)
/// [progressPct] (a continuous double) drives the fill-bar width and is
/// already mathematically exact — it reaches precisely 100.0 on the last
/// page with no rounding involved. [displayPercent] (a pre-computed,
/// display-safe integer from [PdfViewerController.displayPercent]) drives
/// the "NN%" text label and guarantees the first page is never shown as
/// 0%, the last page is always shown as exactly 100%, and every value
/// stays within `[1, 100]` once a document has loaded.
///
/// ### Appearance system
/// All colours come from [ReaderColors] — looked up once per build via
/// `Theme.of(context).extension<ReaderColors>()` — so this pill
/// automatically follows Light / Dark / Follow System.
///
/// ### Performance
/// Wrapped in a [RepaintBoundary]. Colour lookup is a single
/// [ThemeExtension] read per build, not per paint. The watchdog timer
/// ticks at a coarse 200ms interval and does no allocation beyond a single
/// [DateTime.now()] comparison per tick.
class ReaderProgressOverlay extends StatefulWidget {
  const ReaderProgressOverlay({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.progressPct,
    required this.displayPercent,
    this.isSaving = false,
    this.noteCountOnCurrentPage = 0,
  });

  final int currentPage;
  final int totalPages;

  /// Exact continuous progress in `[0.0, 100.0]` — drives the fill-bar
  /// width. Already reaches exactly 100.0 on the last page.
  final double progressPct;

  /// Display-safe integer percent for the text label. Guaranteed never 0%
  /// on the first page and always exactly 100% on the last page. See
  /// [PdfViewerController.displayPercent].
  final int displayPercent;

  final bool isSaving;

  /// Pre-computed by [PdfViewerController.noteCountOnCurrentPage]. Reading
  /// this is O(1) — no inline filtering in the build method.
  final int noteCountOnCurrentPage;

  @override
  State<ReaderProgressOverlay> createState() => _ReaderProgressOverlayState();
}

class _ReaderProgressOverlayState extends State<ReaderProgressOverlay> {
  static const Duration _kVisibleDuration = Duration(seconds: 2);
  static const Duration _kWatchdogInterval = Duration(milliseconds: 200);

  bool _visible = true;
  DateTime _lastActivityAt = DateTime.now();
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _registerActivity();
  }

  @override
  void didUpdateWidget(covariant ReaderProgressOverlay old) {
    super.didUpdateWidget(old);
    // Show only on a genuine page change (page jumps, search, bookmarks,
    // continue-reading restore, manual nav — all of these flow through
    // PdfViewerController._updateCurrentPage, the only thing that changes
    // `currentPage`). Saving-spinner and note-count changes never
    // re-trigger visibility on their own.
    if (old.currentPage != widget.currentPage) {
      _registerActivity();
    }
  }

  /// Cheap, allocation-free on the hot path: just records a timestamp and
  /// ensures a single watchdog timer is running. Safe to call as often as
  /// once per scroll-driven page change during a fast fling — it never
  /// creates a new [Timer] if one is already active.
  void _registerActivity() {
    _lastActivityAt = DateTime.now();
    if (!_visible) {
      setState(() => _visible = true);
    }
    _watchdog ??= Timer.periodic(_kWatchdogInterval, _checkIdle);
  }

  void _checkIdle(Timer timer) {
    if (DateTime.now().difference(_lastActivityAt) >= _kVisibleDuration) {
      timer.cancel();
      _watchdog = null;
      if (mounted && _visible) {
        setState(() => _visible = false);
      }
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _watchdog = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rc = Theme.of(context).extension<ReaderColors>() ??
        ReaderColors.forBrightness(Theme.of(context).brightness);

    final pageLabel = widget.totalPages > 0
        ? 'Page ${widget.currentPage + 1} / ${widget.totalPages}'
        : 'Loading…';
    final pct = widget.totalPages > 0 ? '${widget.displayPercent}%' : '';

    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: IgnorePointer(
        // While fading out, the pill shouldn't intercept taps meant for
        // the PDF content beneath it.
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: AppDurations.medium,
          curve: AppDurations.curve,
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: rc.overlayBackground,
                  borderRadius:
                      const BorderRadius.all(Radius.circular(AppRadius.pill)),
                ),
                child: Row(
                  children: [
                    // ── Note badge (secondary indicator) ─────────────
                    if (widget.noteCountOnCurrentPage > 0) ...[
                      Tooltip(
                        message: '${widget.noteCountOnCurrentPage} '
                            'note${widget.noteCountOnCurrentPage == 1 ? '' : 's'} '
                            'on this page',
                        child: Icon(
                          Icons.sticky_note_2_rounded,
                          size: 14,
                          color: rc.noteBadge,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],

                    // ── Progress bar ──────────────────────────────────
                    Expanded(
                      child: _MiniProgressBar(
                        progressPct: widget.progressPct,
                        trackColor: rc.overlayTrack,
                        fillColor: rc.overlayFill,
                      ),
                    ),

                    const SizedBox(width: AppSpacing.md),

                    // ── Page label ────────────────────────────────────
                    Text(
                      pageLabel,
                      style: TextStyle(
                        color: rc.overlayLabel,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    if (pct.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.xs + 2),
                      Text(pct,
                          style: TextStyle(
                              color: rc.overlayLabelSecondary, fontSize: 11)),
                    ],

                    // ── Saving spinner ────────────────────────────────
                    AnimatedOpacity(
                      opacity: widget.isSaving ? 1.0 : 0.0,
                      duration: AppDurations.medium,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: rc.overlaySavingIndicator,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
/// Uses [FractionallySizedBox]-equivalent explicit width computation
/// inside a [LayoutBuilder] rather than a raw fractional widget so the
/// fill can be wrapped in an [AnimatedContainer] and animate smoothly
/// between page turns.
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({
    required this.progressPct,
    required this.trackColor,
    required this.fillColor,
  });

  final double progressPct;
  final Color trackColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final fraction = (progressPct / 100.0).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: SizedBox(
        height: 4,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final totalW = constraints.maxWidth;
            final fillW = fraction * totalW;
            return Stack(
              children: [
                // Track
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const SizedBox.expand(),
                ),
                // Fill
                AnimatedContainer(
                  duration: AppDurations.slow,
                  curve: AppDurations.curve,
                  width: fillW,
                  height: 4,
                  decoration: BoxDecoration(
                    color: fillColor,
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
