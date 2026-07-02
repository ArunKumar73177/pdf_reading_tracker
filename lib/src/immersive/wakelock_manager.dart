import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Ref-counted wrapper around `wakelock_plus`.
///
/// Ref-counting (rather than a single on/off boolean) matters when more
/// than one [PdfReadingTrackerViewer] can be alive at once — e.g. a host
/// app that keeps a previous reader screen in the navigation stack, or a
/// split-screen / multi-window layout. Without ref-counting, viewer B
/// disposing while viewer A is still on-screen with Keep Screen Awake
/// enabled would incorrectly release the wakelock out from under A.
///
/// This class never throws: `wakelock_plus` calls are wrapped so a
/// platform-channel failure (e.g. an unsupported embedder) degrades to a
/// no-op instead of crashing the reader.
///
/// ### Audit fix — resume re-assertion
/// [reapplyIfActive] was added after an engineering audit identified that
/// some OEM battery-optimization skins silently clear the screen-on window
/// flag when an app is backgrounded for an extended period. This method
/// re-asserts the wakelock **without** touching [_refCount] — it is not a
/// new enable/disable, just defensively re-stating existing state on
/// resume. It is a no-op (does not call the platform at all) when nothing
/// is currently active, so it never introduces an unnecessary platform
/// channel call for readers that never enabled Keep Screen Awake.
class WakelockManager {
  WakelockManager._();
  static final WakelockManager instance = WakelockManager._();

  int _refCount = 0;

  Future<void> enable() async {
    _refCount++;
    if (_refCount != 1) return; // already active on behalf of another viewer
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[WakelockManager] enable failed (non-fatal): $e');
    }
  }

  Future<void> disable() async {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount != 0) return; // still needed by another viewer
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('[WakelockManager] disable failed (non-fatal): $e');
    }
  }

  /// Re-asserts the wakelock on app resume if it should currently be
  /// active. Does not change [_refCount] — this is idempotent re-statement,
  /// not a new acquisition. See class doc.
  Future<void> reapplyIfActive() async {
    if (_refCount <= 0) return;
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[WakelockManager] reapplyIfActive failed (non-fatal): $e');
    }
  }
}