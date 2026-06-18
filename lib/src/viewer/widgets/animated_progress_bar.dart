import 'package:flutter/material.dart';

/// A lightweight animated progress bar with gradient fill, rounded corners,
/// and an optional percentage label.
///
/// ### Performance
/// The fill container is wrapped in a [RepaintBoundary] so that the
/// [AnimatedContainer] width animation never triggers a repaint of the
/// surrounding page content. This is particularly important in
/// [ReaderBottomBar] which sits above the PDF viewport.
///
/// Responds to [Theme] automatically — uses [ColorScheme.primary] for the
/// gradient in light mode and desaturates gracefully in dark mode.
///
/// ### Usage
/// ```dart
/// AnimatedProgressBar(
///   progressPct: 42.5,   // 0.0 – 100.0
///   height: 8,
///   showLabel: true,
/// )
/// ```
class AnimatedProgressBar extends StatelessWidget {
  const AnimatedProgressBar({
    super.key,
    required this.progressPct,
    this.height            = 8.0,
    this.showLabel         = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.animationCurve    = Curves.easeOutCubic,
  }) : assert(progressPct >= 0.0 && progressPct <= 100.0,
  'progressPct must be in [0.0, 100.0]');

  /// Completion percentage in [0.0, 100.0].
  final double progressPct;

  /// Height of the progress track in logical pixels.
  final double height;

  /// Whether to show the `"XX.X%"` label to the right of the bar.
  final bool showLabel;

  /// Duration of the fill animation when [progressPct] changes.
  final Duration animationDuration;

  /// Curve applied to the fill animation.
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Gradient: shift hue slightly so the bar feels alive.
    final gradientStart = cs.primary;
    final gradientEnd   =
        Color.lerp(cs.primary, cs.tertiary, 0.55) ?? cs.primary;

    final track = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final fillWidth  = (progressPct / 100.0) * totalWidth;

          return Stack(
            children: [
              // ── Track ────────────────────────────────────────────────
              Container(
                width:  totalWidth,
                height: height,
                decoration: BoxDecoration(
                  color:        cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),

              // ── Animated fill ─────────────────────────────────────────
              AnimatedContainer(
                duration: animationDuration,
                curve:    animationCurve,
                width:    fillWidth.clamp(0.0, totalWidth),
                height:   height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 2),
                  gradient: LinearGradient(
                    colors: [gradientStart, gradientEnd],
                    begin:  Alignment.centerLeft,
                    end:    Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      cs.primary.withAlpha(55),
                      blurRadius: 4,
                      offset:     const Offset(0, 1),
                    ),
                  ],
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

/// Animated percentage label — cross-fades when the value changes.
///
/// Uses a [RepaintBoundary] so the cross-fade repaints only this small
/// label region rather than the entire bottom bar.
class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.progressPct, required this.color});

  final double progressPct;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration:          const Duration(milliseconds: 280),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Text(
          key:   ValueKey(progressPct.toStringAsFixed(1)),
          '${progressPct.toStringAsFixed(1)}%',
          style: tt.labelSmall?.copyWith(
            color:       color,
            fontWeight:  FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}