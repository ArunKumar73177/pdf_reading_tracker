import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Wraps the PDF viewer surface with a single-tap-to-toggle-chrome
/// gesture, without interfering with Syncfusion's own gestures.
///
/// ### Runtime re-audit — why the previous `GestureDetector.onTap`
/// approach was replaced
///
/// The prior version used an ancestor `GestureDetector` declaring only
/// `onTap`. That's correct in isolation, but `SfPdfViewer` installs its
/// own internal recognizers (pan/scroll, pinch/scale, double-tap zoom,
/// long-press selection-start, and a tap recognizer used to dismiss an
/// active selection). Every `TapGestureRecognizer` hit-tested for the
/// same pointer lands in **one shared gesture arena**, and arena
/// resolution for a plain tap is decided by sweep order — because
/// hit-testing walks front-to-back, Syncfusion's innermost recognizer
/// enters the arena first and wins, silently swallowing our outer
/// `onTap` on exactly the taps that matter most (e.g. the first tap
/// after a selection was active). This is invisible under code review —
/// every line "looks" correct — and only shows up on-device. It is the
/// most likely explanation for a user getting stuck with no visible
/// controls in Immersive Mode.
///
/// ### Fix — raw pointer routing instead of a competing recognizer
///
/// [Listener] receives every [PointerDownEvent]/[PointerUpEvent] for its
/// hit-test region unconditionally — pointer *routing* happens before any
/// gesture arena is formed, so nothing Syncfusion does internally can
/// claim or suppress these events. A tap is recognized manually:
/// - single pointer only (a second finger touching down cancels tap
///   tracking outright — never mistaken for a pinch),
/// - movement under [_kTapSlop] (so a pan/scroll/pinch/selection-drag
///   is never treated as a tap — preserves scroll not revealing chrome),
/// - completes within [_kTapTimeout] (so a long-press-to-select, which
///   runs past this, is never treated as a tap),
/// - and — because Double Tap Zoom outranks Single Tap in priority — a
///   recognized tap is held for `kDoubleTapTimeout` before firing
///   [onTap]; if a second tap starts within that window it's cancelled,
///   leaving Syncfusion's own double-tap-zoom recognizer to handle it
///   cleanly with no chrome flicker.
///
/// Because `Listener` never enters the arena, it also never delays or
/// blocks Syncfusion's own pinch/double-tap/selection recognizers — it
/// only observes the same raw events they receive.
class ImmersiveGestureLayer extends StatefulWidget {
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
  State<ImmersiveGestureLayer> createState() => _ImmersiveGestureLayerState();
}

class _ImmersiveGestureLayerState extends State<ImmersiveGestureLayer> {
  // Comfortably above a typical fast tap, comfortably below Flutter's
  // long-press threshold (~500ms) — so long-press-to-select is never
  // misidentified as a tap.
  static const Duration _kTapTimeout = Duration(milliseconds: 350);
  static const double _kTapSlop = 18.0;

  int _activePointerCount = 0;
  Offset? _downPosition;
  DateTime? _downTime;
  Timer? _pendingTapTimer;

  void _onPointerDown(PointerDownEvent event) {
    _activePointerCount++;

    if (_activePointerCount > 1) {
      // A second finger touched down mid-gesture — at minimum a pinch
      // candidate, never a single tap. Drop any tap tracking entirely.
      _downPosition = null;
      _downTime = null;
      _pendingTapTimer?.cancel();
      _pendingTapTimer = null;
      return;
    }

    if (_pendingTapTimer != null) {
      // A tap was already pending disambiguation and a new pointer just
      // went down quickly — this is a double tap. Cancel the pending
      // single-tap toggle and let Syncfusion's own double-tap-zoom
      // recognizer own the gesture.
      _pendingTapTimer!.cancel();
      _pendingTapTimer = null;
    }

    _downPosition = event.position;
    _downTime = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointerCount = (_activePointerCount - 1).clamp(0, 1 << 30);

    final downPos = _downPosition;
    final downTime = _downTime;
    _downPosition = null;
    _downTime = null;
    if (downPos == null || downTime == null) return;

    final movedDistance = (event.position - downPos).distance;
    final elapsed = DateTime.now().difference(downTime);
    if (movedDistance > _kTapSlop || elapsed > _kTapTimeout) return;

    // Hold briefly to see if a second tap follows (double-tap zoom).
    _pendingTapTimer?.cancel();
    _pendingTapTimer = Timer(kDoubleTapTimeout, () {
      _pendingTapTimer = null;
      widget.onTap();
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointerCount = (_activePointerCount - 1).clamp(0, 1 << 30);
    _downPosition = null;
    _downTime = null;
  }

  @override
  void dispose() {
    _pendingTapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
