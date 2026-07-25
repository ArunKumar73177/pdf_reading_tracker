import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/theme_extensions.dart';

// ---------------------------------------------------------------------------
// ReaderProgressOverlay
// ---------------------------------------------------------------------------

/// Compact floating progress pill shown at the bottom of the PDF viewport.
///
/// ### Redesign note — visibility ownership moved to the caller
///
/// This widget used to be a [StatefulWidget] that ran its own independent
/// `Timer.periodic` "watchdog": it faded itself out after ~2 seconds of
/// inactivity and faded back in on every page change, entirely on its
/// own. That had two problems:
///
/// 1. It fired **regardless of Immersive Mode** — meaning the pill could
///    silently auto-hide even in classic (non-immersive) mode, where the
///    reader chrome is supposed to stay permanently visible.
/// 2. It duplicated (and could visually race with) the tap-driven
///    auto-hide timer already owned by `ImmersiveVisibilityController`,
///    which is the single source of truth for "is the reader chrome
///    showing right now" for the app bar and FAB.
///
/// This widget is now a pure, stateless, timer-free function of its
/// constructor parameters. The caller
/// (`PdfReadingTrackerViewerState._buildOverlayStack`) is solely
/// responsible for visibility: permanently shown in classic mode, tied to
/// the same `ImmersiveVisibilityController.chromeVisible` signal the app
/// bar and FAB already use in immersive mode.
///
/// ### Positioning fix
///
/// This widget deliberately does **not** wrap itself in a [Positioned].
/// [Positioned] is a [ParentDataWidget]: it only takes effect when it is
/// the outermost widget sitting directly inside a [Stack], with nothing
/// but non-render-object widgets (like [ListenableBuilder]) between them.
/// If it is nested *inside* other render-object widgets — e.g.
/// `Stack(children: [ListenableBuilder(builder: (_, __) => IgnorePointer(
/// child: AnimatedOpacity(child: Positioned(...))))])` — the parent-data
/// offsets it sets never reach the [Stack]'s actual render child and are
/// silently dropped, so `left` / `right` / `bottom` have no effect. That
/// was exactly how this widget was previously being used, which meant
/// the "always overlay above the PDF at the bottom" guarantee wasn't
/// reliably held. The caller now wraps this widget as
/// `Positioned(left: ..., right: ..., bottom: ..., child: <visibility
/// wrappers> child: ReaderProgressOverlay(...))` — [Positioned] outermost,
/// [IgnorePointer] / [AnimatedSlide] / [AnimatedOpacity] nested *inside*
/// it — which is the pattern the plugin's own immersive app bar already
/// (correctly) uses.
///
/// ### Note badge (secondary indicator)
/// When [noteCountOnCurrentPage] > 0, a small note icon appears to the
/// left of the progress bar. This is a secondary indicator; the primary
/// indicator is the in-PDF highlight annotation added by
/// [PdfViewerController.addNote].
///
/// ### Progress display correctness
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
/// automatically follows Light / Dark / Follow System. A subtle
/// frosted-glass blur sits behind the pill for a premium, modern
/// (Kindle / Moon+ Reader-style) feel.
///
/// ### Performance
/// Wrapped in a [RepaintBoundary]. No [Timer], no [ChangeNotifier]
/// subscription of its own — a pure presentational widget. Colour lookup
/// is a single [ThemeExtension] read per build.
class ReaderProgressOverlay extends StatelessWidget {
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

  static const double _kHeight = 40.0;
  static const double _kBlurSigma = 18.0;

  @override
  Widget build(BuildContext context) {
    final rc = Theme.of(context).extension<ReaderColors>() ??
        ReaderColors.forBrightness(Theme.of(context).brightness);

    final pageLabel =
        totalPages > 0 ? 'Page ${currentPage + 1} of $totalPages' : 'Loading…';
    final pct = totalPages > 0 ? '$displayPercent%' : '';

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _kBlurSigma, sigmaY: _kBlurSigma),
          child: Container(
            height: _kHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: rc.overlayBackground,
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadius.pill)),
              border: Border.all(
                color: rc.overlayLabelSecondary.withAlpha(38),
                width: 0.75,
              ),
            ),
            child: Row(
              children: [
                // ── Note badge (secondary indicator) ─────────────
                if (noteCountOnCurrentPage > 0) ...[
                  Tooltip(
                    message: '$noteCountOnCurrentPage '
                        'note${noteCountOnCurrentPage == 1 ? '' : 's'} '
                        'on this page',
                    child: Icon(
                      Icons.sticky_note_2_rounded,
                      size: 13,
                      color: rc.noteBadge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],

                // ── Progress bar ──────────────────────────────────
                Expanded(
                  child: _MiniProgressBar(
                    progressPct: progressPct,
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
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),

                if (pct.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs + 2),
                  Text(
                    pct,
                    style: TextStyle(
                      color: rc.overlayLabelSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],

                // ── Saving spinner ────────────────────────────────
                AnimatedOpacity(
                  opacity: isSaving ? 1.0 : 0.0,
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
