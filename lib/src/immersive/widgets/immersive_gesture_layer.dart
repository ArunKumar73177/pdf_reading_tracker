import 'package:flutter/material.dart';

/// Wraps the PDF viewer surface with a single-tap-to-toggle-chrome
/// gesture, without interfering with any of Syncfusion's own gestures.
///
/// ### Why this is safe alongside `SfPdfViewer`
///
/// `SfPdfViewer` owns its own internal gesture recognizers for double-tap
/// zoom, long-press text-selection start, and pinch-to-zoom. This widget
/// registers **only** a [GestureDetector.onTap] — it never declares
/// `onDoubleTap` or `onLongPress`. Because Flutter's gesture arena only
/// disambiguates between recognizers that are actually competing for the
/// same gesture *type*, an ancestor `onTap`-only recognizer does not
/// introduce the double-tap detection delay (`kDoubleTapTimeout`) into
/// `SfPdfViewer`'s own double-tap handling, and does not need to "lose" to
/// it — single taps that aren't claimed by anything else simply reach
/// here.
///
/// ### Placement matters
///
/// This must wrap only the PDF surface itself (`_PdfViewerCore`), **not**
/// the annotation action bar, progress pill, or app bar — those are
/// separate `Positioned` siblings in the same `Stack`, not descendants of
/// this widget, so their own buttons are entirely unaffected and never
/// trigger the immersive toggle.
///
/// ### Zero overhead when disabled
///
/// When [enabled] is `false` (Immersive Mode is off), this widget skips
/// allocating a `GestureDetector` entirely and returns [child] directly —
/// there is no hit-testing or gesture-arena cost at all in the default,
/// non-immersive reading mode.
class ImmersiveGestureLayer extends StatelessWidget {
  const ImmersiveGestureLayer({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: child,
    );
  }
}