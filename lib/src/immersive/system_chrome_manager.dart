import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ref-counted wrapper around [SystemChrome.setEnabledSystemUIMode].
///
/// Bound to the *session* of Immersive Mode being on — called once when
/// Immersive Mode is toggled on/off in Reading Settings, never on every
/// per-tap chrome show/hide inside an immersive session. Calling a
/// platform channel method on every tap would be wasteful and is exactly
/// the kind of "unnecessary call" the Phase 3 brief warns against. Hiding
/// the *in-app* chrome (via [ImmersiveVisibilityController]) is what
/// handles the frequent per-tap toggling; this class only handles the
/// coarse-grained, rare system-status-bar transition.
///
/// Ref-counted for the same multi-viewer-instance reason as
/// [WakelockManager].
///
/// ### Audit fix — resume re-assertion
/// Android clears `SystemUiMode.immersiveSticky` whenever the app returns
/// to the foreground after being backgrounded — the system status/nav
/// bars reappear even though nothing in the reader's own state changed.
/// [reapplyIfActive] re-issues the same mode on
/// [AppLifecycleState.resumed] **without** incrementing [_refCount] (this
/// is re-assertion of existing state, not a new session), fixing the bug
/// where immersive mode silently "fell out" of full-bleed after
/// switching apps and coming back.
class SystemChromeManager {
  SystemChromeManager._();
  static final SystemChromeManager instance = SystemChromeManager._();

  int _refCount = 0;

  Future<void> enterImmersive() async {
    _refCount++;
    if (_refCount != 1) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint(
          '[SystemChromeManager] enterImmersive failed (non-fatal): $e');
    }
  }

  Future<void> exitImmersive() async {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount != 0) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint(
          '[SystemChromeManager] exitImmersive failed (non-fatal): $e');
    }
  }

  /// Re-issues [SystemUiMode.immersiveSticky] on app resume if it should
  /// currently be active. Does not change [_refCount]. No-op — and no
  /// platform channel call at all — when immersive mode isn't currently
  /// active for any viewer. See class doc.
  Future<void> reapplyIfActive() async {
    if (_refCount <= 0) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint(
          '[SystemChromeManager] reapplyIfActive failed (non-fatal): $e');
    }
  }
}