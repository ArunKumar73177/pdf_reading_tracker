import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dnd_service_unsupported.dart';

/// How usable Do Not Disturb integration is on the current platform.
enum DndSupportLevel {
  /// Fully wired up and working right now.
  fullSupport,

  /// Technically possible but with caveats (unused in Phase 3A).
  partialSupport,

  /// The platform provides no public API for this at all — never show
  /// this as "coming soon"; it will never be possible.
  notSupported,

  /// The platform *could* support this (a real implementation is planned)
  /// but Phase 3A hasn't wired it up yet.
  comingSoon,
}

/// Describes what a [DndService] can actually do, plus a human-readable
/// reason a host-app developer can surface directly in their own UI even
/// if they don't use `showReadingSettingsSheet`.
@immutable
class DndCapability {
  const DndCapability({required this.level, required this.reason});

  final DndSupportLevel level;
  final String reason;

  /// `true` only for levels where calling [DndService.enable] can
  /// meaningfully do something.
  bool get isUsable =>
      level == DndSupportLevel.fullSupport ||
          level == DndSupportLevel.partialSupport;

  @override
  String toString() => 'DndCapability(level: $level, reason: $reason)';
}

/// Platform-agnostic Do Not Disturb control surface.
///
/// **Final Reader-integration pass:**
/// - [disable] now takes an optional [restoreFilter] so the caller
///   (`ReadingSettingsController`) can restore the *exact* interruption
///   filter that was in effect before DND was enabled, instead of
///   blindly resetting to "all interruptions allowed". Omitting it keeps
///   the old behavior (native side falls back to
///   `INTERRUPTION_FILTER_ALL`) — no existing caller breaks.
/// - [getCurrentInterruptionFilter] lets a caller capture that
///   "before" state right before calling [enable].
///
/// Everything else — including the [enable]/[requestAccess] contract —
/// is unchanged from Phase 3A/3B.
abstract class DndService {
  DndCapability get capability;

  /// Requests whatever platform permission Do Not Disturb needs (a no-op
  /// returning `false` on platforms where [capability]`.isUsable` is
  /// `false`).
  ///
  /// This method's contract intentionally includes *navigation*: on
  /// platforms where permission can only be granted by the user in
  /// system settings, calling this when permission is not yet granted
  /// opens that settings screen as a side effect. Callers that only want
  /// to read current status — e.g. a future Reader re-checking on
  /// `AppLifecycleState.resumed`, without risking an unwanted repeat
  /// Settings navigation — should use [checkPermission] instead.
  ///
  /// This is the ONLY method in the entire `DndService` surface that may
  /// prompt the user for permission. `ReadingSettingsController` is the
  /// only call site that invokes it, and only from the explicit
  /// "user flipped the DND switch on" action.
  Future<bool> requestAccess();

  /// Reads current permission status with no navigation side effect.
  Future<bool> checkPermission() async => false;

  /// Reads the interruption filter currently in effect, or `null` if it
  /// couldn't be determined (unsupported platform, channel failure,
  /// etc). Read-only — never requires Notification Policy Access.
  Future<int?> getCurrentInterruptionFilter();

  Future<void> enable();

  /// Turns Do Not Disturb off.
  ///
  /// [restoreFilter] — if provided — is the exact interruption-filter
  /// value to restore (typically whatever [getCurrentInterruptionFilter]
  /// returned right before [enable] was called). If omitted or `null`,
  /// implementations fall back to a safe default rather than restoring
  /// nothing.
  Future<void> disable({int? restoreFilter});

  void dispose();
}

/// Android [DndService] implementation, backed by the `pdf_reading_tracker`
/// `MethodChannel` and the native `DndManager` / `PdfReadingTrackerPlugin`.
///
/// Every native call is wrapped so a [PlatformException] (or any other
/// failure — a stale/detached channel, a missing native implementation on
/// an unexpected OEM build, etc.) degrades gracefully instead of
/// propagating into the reader: methods that return a value fall back to
/// a safe default (`false`/`null`), and fire-and-forget methods ([enable],
/// [disable]) simply become no-ops.
///
/// [capability] does not need a native round-trip to compute: the
/// package's Android `minSdk` is 24, and the native `isSupported()` check
/// (`SDK_INT >= M` / API 23) is therefore always `true` in practice. It is
/// reported here as a plain constant for that reason, matching the native
/// side's own comment.
class AndroidDndService implements DndService {
  AndroidDndService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('pdf_reading_tracker');

  final MethodChannel _channel;

  @override
  DndCapability get capability => const DndCapability(
    level: DndSupportLevel.fullSupport,
    reason: 'Do Not Disturb is available on this device. Granting '
        'Notification Policy Access lets the reader silence '
        'notifications while Immersive Mode is on.',
  );

  /// Whether Notification Policy Access is currently granted.
  ///
  /// Pure status read — no navigation, no side effects. Never throws: any
  /// failure (including [PlatformException]) is treated as "not granted"
  /// rather than crashing the caller.
  @override
  Future<bool> checkPermission() async {
    try {
      final granted =
      await _channel.invokeMethod<bool>('isPermissionGranted');
      return granted ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestAccess() async {
    try {
      if (await checkPermission()) return true;
      // Notification Policy Access can only be granted by the user in
      // system settings — there is no in-app permission dialog. This
      // opens that settings screen; it does NOT block until the user
      // returns, so the return value reflects the pre-navigation state.
      // Callers that need the post-navigation result should poll
      // [checkPermission] (e.g. on app resume) rather than call this
      // method again.
      await _channel.invokeMethod<void>('openPermissionSettings');
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the live interruption filter via the native
  /// `getCurrentInterruptionFilter` method. This is a read — it never
  /// requires Notification Policy Access — so failures here are treated
  /// purely as "couldn't determine it" (`null`), never surfaced to the
  /// reader as an error.
  @override
  Future<int?> getCurrentInterruptionFilter() async {
    try {
      return await _channel.invokeMethod<int>('getCurrentInterruptionFilter');
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> enable() async {
    try {
      await _channel.invokeMethod<void>('enableDnd');
    } on PlatformException {
      // Native side already no-ops safely without permission; this catch
      // only guards against channel-level failures (e.g. engine
      // detachment) so the reader is never disrupted.
    } catch (_) {
      // Swallow — enabling DND must never crash the reader.
    }
  }

  /// [restoreFilter], when provided, is forwarded to the native side as
  /// `{"filter": restoreFilter}` so it can restore that exact
  /// interruption filter instead of assuming `INTERRUPTION_FILTER_ALL`.
  /// The native method name (`disableDnd`) is unchanged — only an
  /// additional, optional argument is now sent.
  @override
  Future<void> disable({int? restoreFilter}) async {
    try {
      await _channel.invokeMethod<void>(
        'disableDnd',
        restoreFilter != null ? <String, dynamic>{'filter': restoreFilter} : null,
      );
    } on PlatformException {
      // See enable().
    } catch (_) {
      // Swallow — disabling DND must never crash the reader.
    }
  }

  @override
  void dispose() {
    // No persistent resources (streams, subscriptions, timers) are held
    // by this service — each call is a one-shot MethodChannel invocation.
  }
}

/// Resolves the correct [DndService] for the running platform.
///
/// Android: [AndroidDndService], talking to the real native
/// implementation.
/// iOS / everything else: [UnsupportedDndService], unchanged from
/// Phase 3A — see `dnd_service_unsupported.dart`.
abstract final class DndServiceProvider {
  static DndService create() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidDndService();
    }
    if (!kIsWeb && Platform.isIOS) {
      return const UnsupportedDndService(
        DndCapability(
          level: DndSupportLevel.notSupported,
          reason: 'iOS does not expose a public API to toggle Do Not '
              'Disturb or Focus modes. This is a platform limitation, '
              'not a missing feature — it will never be possible from '
              'a third-party app.',
        ),
      );
    }
    return const UnsupportedDndService(
      DndCapability(
        level: DndSupportLevel.notSupported,
        reason: 'Do Not Disturb is a mobile-notification concept and has '
            'no equivalent on this platform. Use Immersive Mode for a '
            'distraction-free reading surface here instead.',
      ),
    );
  }
}