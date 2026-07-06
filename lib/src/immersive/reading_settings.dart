import 'package:flutter/foundation.dart';

/// Immutable snapshot of the reader's distraction-free reading preferences.
///
/// Persisted via `ReadingSettingsStorage` as a tiny JSON file — mirrors the
/// storage strategy already used by `AppearanceStorage` (Phase 1). No
/// database table is added; this is intentional (Phase 3 brief: "DO NOT
/// MODIFY ... Database").
///
/// **Forward compatibility (Phase 3B):** [dndEnabled] is present now and
/// persisted, but has **no runtime effect** in Phase 3A — no DND service is
/// wired up yet (see `dnd/dnd_service.dart`). Keeping the field here means
/// Phase 3B can activate real Android DND without a settings-file migration
/// or a breaking change to this class.
@immutable
class ReadingSettings {
  const ReadingSettings({
    required this.immersiveModeEnabled,
    required this.keepScreenAwakeEnabled,
    required this.autoHideControlsEnabled,
    required this.dndEnabled,
  });

  /// Sensible, non-surprising defaults for a first-time reader: nothing
  /// changes until the user opts in via the Reading Settings sheet.
  const ReadingSettings.defaults()
      : immersiveModeEnabled = false,
        keepScreenAwakeEnabled = false,
        autoHideControlsEnabled = true,
        dndEnabled = false;

  /// When `true`, the app bar / bottom controls are hidden by default and
  /// toggled by a single tap on the page. When `false`, the reader behaves
  /// exactly as it did before Phase 3 (chrome always visible).
  final bool immersiveModeEnabled;

  /// When `true`, the device screen is prevented from sleeping while this
  /// viewer is mounted (via `wakelock_plus`).
  final bool keepScreenAwakeEnabled;

  /// When `true` (and [immersiveModeEnabled] is also `true`), the reader
  /// chrome automatically fades out after a short idle period and
  /// reappears on the next tap. Has no effect outside Immersive Mode.
  final bool autoHideControlsEnabled;

  /// Reserved for Phase 3B (Android Do Not Disturb). Persisted for
  /// forward-compatibility only — see class doc.
  final bool dndEnabled;

  ReadingSettings copyWith({
    bool? immersiveModeEnabled,
    bool? keepScreenAwakeEnabled,
    bool? autoHideControlsEnabled,
    bool? dndEnabled,
  }) {
    return ReadingSettings(
      immersiveModeEnabled: immersiveModeEnabled ?? this.immersiveModeEnabled,
      keepScreenAwakeEnabled:
          keepScreenAwakeEnabled ?? this.keepScreenAwakeEnabled,
      autoHideControlsEnabled:
          autoHideControlsEnabled ?? this.autoHideControlsEnabled,
      dndEnabled: dndEnabled ?? this.dndEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'immersiveModeEnabled': immersiveModeEnabled,
        'keepScreenAwakeEnabled': keepScreenAwakeEnabled,
        'autoHideControlsEnabled': autoHideControlsEnabled,
        'dndEnabled': dndEnabled,
      };

  factory ReadingSettings.fromJson(Map<String, dynamic> json) {
    const fallback = ReadingSettings.defaults();
    return ReadingSettings(
      immersiveModeEnabled: json['immersiveModeEnabled'] as bool? ??
          fallback.immersiveModeEnabled,
      keepScreenAwakeEnabled: json['keepScreenAwakeEnabled'] as bool? ??
          fallback.keepScreenAwakeEnabled,
      autoHideControlsEnabled: json['autoHideControlsEnabled'] as bool? ??
          fallback.autoHideControlsEnabled,
      dndEnabled: json['dndEnabled'] as bool? ?? fallback.dndEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReadingSettings &&
        other.immersiveModeEnabled == immersiveModeEnabled &&
        other.keepScreenAwakeEnabled == keepScreenAwakeEnabled &&
        other.autoHideControlsEnabled == autoHideControlsEnabled &&
        other.dndEnabled == dndEnabled;
  }

  @override
  int get hashCode => Object.hash(
        immersiveModeEnabled,
        keepScreenAwakeEnabled,
        autoHideControlsEnabled,
        dndEnabled,
      );

  @override
  String toString() => 'ReadingSettings('
      'immersive: $immersiveModeEnabled, '
      'keepAwake: $keepScreenAwakeEnabled, '
      'autoHide: $autoHideControlsEnabled, '
      'dnd: $dndEnabled)';
}
