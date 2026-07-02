import 'dart:io';

import 'package:flutter/foundation.dart';

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
/// **Phase 3A note:** every platform currently resolves to
/// [UnsupportedDndService] via [DndServiceProvider.create] — no permission
/// is requested, no platform channel is created, no native code is added
/// to this package in this phase (per explicit instruction: "Do NOT
/// implement Android DND yet" / "Do not convert the package into a
/// Flutter plugin in this phase").
///
/// **Phase 3B plan:** `DndServiceProvider.create()` will branch on
/// `Platform.isAndroid` and return a new `AndroidDndService` (backed by a
/// `MethodChannel` calling `NotificationManager.setInterruptionFilter`,
/// gated on the user granting `ACCESS_NOTIFICATION_POLICY`). No call site
/// outside this file will need to change — [ReadingSettingsController],
/// the Reading Settings sheet, and [PdfReadingTrackerViewer] all already
/// depend only on this abstract [DndService] interface and
/// [DndCapability], never on a concrete implementation.
abstract class DndService {
  DndCapability get capability;

  /// Requests whatever platform permission Do Not Disturb needs (a no-op
  /// returning `false` on platforms where [capability]`.isUsable` is
  /// `false`).
  Future<bool> requestAccess();

  Future<void> enable();

  Future<void> disable();

  void dispose();
}

/// Phase 3A's only [DndService] implementation: does nothing, and is
/// honest about why via [capability].
class UnsupportedDndService implements DndService {
  const UnsupportedDndService(this.capability);

  @override
  final DndCapability capability;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}

  @override
  void dispose() {}
}

/// Resolves the correct [DndService] for the running platform.
///
/// Phase 3A: always [UnsupportedDndService], with a platform-appropriate
/// [DndCapability] message. See class doc on [DndService] for the Phase 3B
/// plan.
abstract final class DndServiceProvider {
  static DndService create() {
    if (!kIsWeb && Platform.isAndroid) {
      return const UnsupportedDndService(
        DndCapability(
          level: DndSupportLevel.comingSoon,
          reason: 'Real Do Not Disturb is planned for a future update. '
              'It will require one-time Notification Policy Access '
              'permission.',
        ),
      );
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