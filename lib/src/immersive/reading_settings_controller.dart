import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'reading_settings.dart';
import 'reading_settings_storage.dart';
import 'system_chrome_manager.dart';
import 'wakelock_manager.dart';

/// Owns the current [ReadingSettings], persists changes, and drives the
/// two side-effecting singletons ([WakelockManager], [SystemChromeManager])
/// that must stay in sync with it.
///
/// Lifecycle mirrors `AppearanceController`: created once per
/// [PdfReadingTrackerViewer] instance in `initState`, disposed once in
/// `dispose`.
///
/// **Why this does not live inside `PdfViewerController`:** the Phase 3
/// brief explicitly forbids touching the Progress/Geometry/Database engine
/// that `PdfViewerController` owns. Keeping reading-chrome preferences in a
/// fully separate controller means Phase 3 adds a new, independent unit
/// rather than growing an already-large existing class.
///
/// ### Audit fix — app lifecycle awareness
/// Added `WidgetsBindingObserver` (same pattern as `AppearanceController`
/// already uses for `didChangePlatformBrightness`). On
/// [AppLifecycleState.resumed], both [SystemChromeManager.reapplyIfActive]
/// and [WakelockManager.reapplyIfActive] are called — these are no-ops
/// (skip the platform channel entirely) unless this controller currently
/// has immersive mode / keep-awake active, so backgrounding-and-returning
/// a reader that never enabled either feature costs nothing extra.
class ReadingSettingsController extends ChangeNotifier
    with WidgetsBindingObserver {
  ReadingSettingsController({ReadingSettings? initial})
      : _value = initial ?? const ReadingSettings.defaults() {
    WidgetsBinding.instance.addObserver(this);
  }

  ReadingSettings _value;
  ReadingSettings get value => _value;

  bool _initialized = false;
  bool _wakelockActive = false;
  bool _systemChromeActive = false;

  /// Loads the persisted settings, if any, then syncs side effects
  /// (wakelock / system UI mode) to match. Safe to call once; subsequent
  /// calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final stored = await ReadingSettingsStorage.instance.load();
    if (stored != null && stored != _value) {
      _value = stored;
      notifyListeners();
    }
    await _syncSideEffects();
  }

  Future<void> setImmersiveMode(bool enabled) =>
      _update(_value.copyWith(immersiveModeEnabled: enabled));

  Future<void> setKeepScreenAwake(bool enabled) =>
      _update(_value.copyWith(keepScreenAwakeEnabled: enabled));

  Future<void> setAutoHideControls(bool enabled) =>
      _update(_value.copyWith(autoHideControlsEnabled: enabled));

  /// Persists the user's DND *intent* only. No-op at runtime in Phase 3A —
  /// see [ReadingSettings.dndEnabled] and `dnd/dnd_service.dart`.
  Future<void> setDndEnabled(bool enabled) =>
      _update(_value.copyWith(dndEnabled: enabled));

  Future<void> _update(ReadingSettings next) async {
    if (next == _value) return;
    _value = next;
    notifyListeners();
    await _syncSideEffects();
    unawaited(ReadingSettingsStorage.instance.save(next));
  }

  Future<void> _syncSideEffects() async {
    final wantWakelock = _value.keepScreenAwakeEnabled;
    if (wantWakelock != _wakelockActive) {
      _wakelockActive = wantWakelock;
      wantWakelock
          ? await WakelockManager.instance.enable()
          : await WakelockManager.instance.disable();
    }

    final wantSystemChrome = _value.immersiveModeEnabled;
    if (wantSystemChrome != _systemChromeActive) {
      _systemChromeActive = wantSystemChrome;
      wantSystemChrome
          ? await SystemChromeManager.instance.enterImmersive()
          : await SystemChromeManager.instance.exitImmersive();
    }
  }

  /// Audit fix: re-asserts immersive system UI + wakelock state whenever
  /// the app returns to the foreground. Both calls are cheap no-ops (skip
  /// the platform channel entirely) when this controller has nothing
  /// active, so this costs nothing for readers not using either feature.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_systemChromeActive) {
      unawaited(SystemChromeManager.instance.reapplyIfActive());
    }
    if (_wakelockActive) {
      unawaited(WakelockManager.instance.reapplyIfActive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_wakelockActive) {
      _wakelockActive = false;
      unawaited(WakelockManager.instance.disable());
    }
    if (_systemChromeActive) {
      _systemChromeActive = false;
      unawaited(SystemChromeManager.instance.exitImmersive());
    }
    super.dispose();
  }
}