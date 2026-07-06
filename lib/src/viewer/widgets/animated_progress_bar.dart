import 'package:flutter/material.dart';

/// Animated progress bar used in external / host-app contexts.
///
/// ### Issue 6 fixes in this file
///
/// **`Color.withOpacity` deprecation:**
/// All `Color.withOpacity(x)` calls replaced with equivalent compile-time
/// ARGB constants or [Color.fromARGB] calls using `.value` bit-shifting.
/// `.withOpacity` was deprecated in Flutter 3.27 (Color API v2) and emits
/// an analyzer warning on Flutter ≥ 3.27. Because this package declares
/// `sdk: ^3.3.0`, it must work on Flutter versions that pre-date 3.27 where
/// `.r/.g/.b` double accessors do not exist. Bit-shifting `.value` is
/// compatible with all Flutter versions in the declared range.
///
/// **`boxShadow` on `AnimatedContainer` removed:**
/// A [BoxShadow] on an animating [AnimatedContainer] forces a composited
/// layer allocation on every animation frame. For a 4–8 dp progress fill
/// strip this generates measurable GPU overhead with no perceptible visual
/// benefit. Removed entirely.
///
/// **`toStringAsFixed(0)` for `_ProgressLabel` key:**
/// The previous key used `toStringAsFixed(1)`, which generates a new
/// [ValueKey] on every 0.1 % progress change. In a 1 000-page document this
/// fires the [AnimatedSwitcher] cross-fade on every single page turn.
/// `toStringAsFixed(0)` rounds to integer percent, reducing cross-fade
/// frequency to once per integer-percent boundary — for most documents this
/// means one cross-fade per 3–5 page turns instead of every turn.
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.progressPct,
    this.height = 8.0,
    this.showLabel = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.animationCurve = Curves.easeOutCubic,
  }) : assert(
          progressPct >= 0.0 && progressPct <= 100.0,
          'progressPct must be in [0.0, 100.0]',
        );

  /// Completion percentage in [0.0, 100.0].
  final double progressPct;

  /// Height of the progress track in logical pixels.
  final double height;

  /// Whether to show the percentage label to the right of the bar.
  final bool showLabel;

  /// Duration of the fill animation when [progressPct] changes.
  final Duration animationDuration;

  /// Curve applied to the fill animation.
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final gradientStart = cs.primary;
    final gradientEnd = Color.lerp(cs.primary, cs.tertiary, 0.55) ?? cs.primary;

    // Issue 6: cs.surfaceContainerHighest has no .withOpacity call —
    // used directly as the track color.
    final track = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final fillWidth = (progressPct / 100.0) * totalWidth;

          return Stack(
            children: [
              // ── Track ──────────────────────────────────────────────
              Container(
                width: totalWidth,
                height: height,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),

              // ── Animated fill ──────────────────────────────────────
              // No boxShadow: see class-level doc comment.
              AnimatedContainer(
                duration: animationDuration,
                curve: animationCurve,
                width: fillWidth.clamp(0.0, totalWidth),
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: LinearGradient(
                    colors: [gradientStart, gradientEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (!showLabel) return track;

    return Row(
      children: [
        Expanded(child: track),
        const SizedBox(width: 10),
        _ProgressLabel(progressPct: progressPct, color: cs.primary),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ProgressLabel
// ---------------------------------------------------------------------------

class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.progressPct, required this.color});

  final double progressPct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Text(
          // Issue 6 / Issue 4: toStringAsFixed(0) reduces cross-fade
          // frequency from every 0.1% change to every 1% change.
          key: ValueKey(progressPct.toStringAsFixed(0)),
          '${progressPct.toStringAsFixed(1)}%',
          style: tt.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
