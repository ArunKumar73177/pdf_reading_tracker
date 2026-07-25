import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'dnd/dnd_service.dart';
import 'reading_settings.dart';
import 'reading_settings_storage.dart';
import 'system_chrome_manager.dart';
import 'wakelock_manager.dart';

/// Owns the current [ReadingSettings], persists changes, and drives the
/// side-effecting singletons/services that must stay in sync with it:
/// [WakelockManager], [SystemChromeManager], and — as of this final
/// Reader-integration pass — [DndService].
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
/// ### App lifecycle awareness
/// `WidgetsBindingObserver` (same pattern `AppearanceController` already
/// uses for `didChangePlatformBrightness`). On
/// [AppLifecycleState.resumed], [SystemChromeManager.reapplyIfActive],
/// [WakelockManager.reapplyIfActive], and DND re-sync ([_syncDnd]) are
/// all called — each is a no-op unless this controller currently has the
/// corresponding feature active/intended, so backgrounding-and-returning
/// a reader that never enabled any of them costs nothing extra.
///
/// ### Final Reader-integration pass — Do Not Disturb
///
/// [DndService] is optional (`dndService` constructor param, nullable):
/// existing call sites that don't pass one keep behaving exactly as
/// before, with DND simply staying inert (`_syncDnd` no-ops when
/// `_dndService == null`).
///
/// Actual Android DND state is reconciled to
/// `immersiveModeEnabled && dndEnabled` in [_syncDnd] — DND's entire
/// purpose is silencing notifications *while immersed in reading*, so
/// this single rule uniformly covers every place that combination can
/// arise: the user flipping the DND switch on, Immersive Mode being
/// turned on while DND is already enabled, the reader opening with both
/// already persisted as `true`, or the app resuming into that state.
///
/// [DndService.requestAccess] (the only method that can prompt the user)
/// is called from exactly one place: [setDndEnabled], and only when the
/// user is explicitly turning DND on. [_syncDnd] itself never requests
/// permission — if it isn't already granted, DND just stays off, with no
/// crash and no dialog.
///
/// The interruption filter in effect immediately before DND is enabled
/// is captured in [_previousInterruptionFilter] and passed back to
/// [DndService.disable] whenever DND is turned off (Immersive Mode
/// turning off, DND being turned off, app backgrounding is NOT one of
/// these — only genuine deactivation — or this controller being
/// disposed), so the device is always returned to exactly the state it
/// was in before, never a hardcoded "allow everything".
class ReadingSettingsController extends ChangeNotifier
    with WidgetsBindingObserver {
  ReadingSettingsController({
    ReadingSettings? initial,
    DndService? dndService,
  })  : _value = initial ?? const ReadingSettings.defaults(),
        _dndService = dndService {
    WidgetsBinding.instance.addObserver(this);
  }

  ReadingSettings _value;
  ReadingSettings get value => _value;

  /// `null` means "no DND integration wired up" — DND simply never
  /// activates, and every DND-related method below becomes a cheap
  /// no-op. Supplied by `PdfReadingTrackerViewerState` using the same
  /// [DndService] instance its Reading Settings sheet already displays.
  final DndService? _dndService;

  bool _initialized = false;
  bool _wakelockActive = false;
  bool _systemChromeActive = false;

  /// Whether this controller has actually turned Android DND on right
  /// now (i.e. called [DndService.enable]) — distinct from
  /// [ReadingSettings.dndEnabled], which is only the user's *persisted
  /// intent*. See class doc for the activation rule.
  bool _dndActive = false;

  /// The system interruption filter that was in effect immediately
  /// before this controller last called [DndService.enable]. Captured
  /// fresh every time DND is actually activated, so deactivating it
  /// later restores exactly what existed before.
  int? _previousInterruptionFilter;

  /// Loads the persisted settings, if any, then syncs side effects
  /// (wakelock / system UI mode / DND) to match. Safe to call once;
  /// subsequent calls are no-ops.
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

  /// Persists the user's DND intent and — this is the ONLY place in the
  /// entire package allowed to request Notification Policy Access —
  /// acts on it immediately when turning DND on:
  ///
  /// - Permission already granted → intent is persisted and [_syncDnd]
  ///   (run via [_update] → [_syncSideEffects]) turns DND on right away,
  ///   provided Immersive Mode is also currently on (see [_syncDnd]).
  /// - Permission not granted → opens Notification Policy Access
  ///   settings via [DndService.requestAccess]. DND is NOT force-enabled;
  ///   the user's intent is still persisted, so DND activates on its own
  ///   next re-sync (app resume, or the next time Immersive Mode is
  ///   toggled) once permission is actually granted.
  ///
  /// Turning DND off — here, or via Immersive Mode turning off, or
  /// [dispose] — always goes through [_syncDnd], which restores
  /// [_previousInterruptionFilter] rather than assuming any particular
  /// filter.
  Future<void> setDndEnabled(bool enabled) async {
    if (enabled == _value.dndEnabled) return;

    if (enabled) {
      final dnd = _dndService;
      if (dnd != null && dnd.capability.isUsable) {
        final granted = await dnd.checkPermission();
        if (!granted) {
          // Sole permission-request call site in the whole package.
          await dnd.requestAccess();
        }
      }
    }

    await _update(_value.copyWith(dndEnabled: enabled));
  }

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

    await _syncDnd();
  }

  /// Reconciles actual Android DND state with
  /// `immersiveModeEnabled && dndEnabled`. See class doc for why both
  /// conditions gate activation.
  ///
  /// Never calls [DndService.requestAccess] — that is the sole
  /// responsibility of [setDndEnabled]. If permission isn't granted when
  /// this method wants DND active, it simply leaves DND inactive and
  /// returns quietly: no crash, no dialog, reader otherwise fully
  /// functional (requirement: permission denied/revoked never disrupts
  /// the reader).
  Future<void> _syncDnd() async {
    final dnd = _dndService;
    if (dnd == null || !dnd.capability.isUsable) return;

    final wantActive = _value.immersiveModeEnabled && _value.dndEnabled;
    if (wantActive == _dndActive) return;

    if (wantActive) {
      final granted = await dnd.checkPermission();
      if (!granted) {
        // Do not request access from here — see class/method docs. The
        // user's intent stays persisted; a later explicit toggle or a
        // resume-after-granting-in-Settings will re-attempt this.
        return;
      }
      try {
        // Capture whatever filter is in effect right now, BEFORE
        // overriding it, so it can be restored exactly later — never a
        // hardcoded "restore to allow everything".
        _previousInterruptionFilter = await dnd.getCurrentInterruptionFilter();
        await dnd.enable();
        _dndActive = true;
      } catch (_) {
        // Never let a DND failure disrupt the reader.
        _dndActive = false;
        _previousInterruptionFilter = null;
      }
    } else {
      if (_dndActive) {
        final restoreFilter = _previousInterruptionFilter;
        _dndActive = false;
        _previousInterruptionFilter = null;
        try {
          await dnd.disable(restoreFilter: restoreFilter);
        } catch (_) {
          // Disabling must never crash the reader (e.g. permission was
          // revoked while the reader was open).
        }
      }
    }
  }

  /// Re-asserts immersive system UI + wakelock state, and re-evaluates
  /// DND, whenever the app returns to the foreground. All three are
  /// cheap no-ops when this controller has nothing active/intended, so
  /// this costs nothing for readers not using these features. The DND
  /// re-sync is a permission *check* only (covers "user granted access
  /// in Settings and came back") — it never requests permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_systemChromeActive) {
      unawaited(SystemChromeManager.instance.reapplyIfActive());
    }
    if (_wakelockActive) {
      unawaited(WakelockManager.instance.reapplyIfActive());
    }
    unawaited(_syncDnd());
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
    if (_dndActive) {
      _dndActive = false;
      final dnd = _dndService;
      final restoreFilter = _previousInterruptionFilter;
      _previousInterruptionFilter = null;
      if (dnd != null) {
        unawaited(dnd.disable(restoreFilter: restoreFilter));
      }
    }
    super.dispose();
  }
}
