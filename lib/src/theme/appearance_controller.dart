import 'package:flutter/material.dart';

import 'appearance_data.dart';
import 'appearance_mode.dart';
import 'appearance_storage.dart';
import 'theme_extensions.dart';

/// Owns the currently-selected [AppearanceMode], resolves it to a concrete
/// [Brightness] / [ThemeData], persists changes, and reacts to system
/// theme changes when [AppearanceMode.system] is active.
///
/// Lifecycle mirrors [PdfViewerController] in the rest of this package:
/// created once per [PdfReadingTrackerViewer] instance in `initState`,
/// disposed once in `dispose`. It is intentionally lightweight — a single
/// enum field, one listener, no heavy state — so mounting it does not add
/// any measurable overhead to viewer startup.
class AppearanceController extends ChangeNotifier with WidgetsBindingObserver {
  AppearanceController({AppearanceMode initialMode = AppearanceMode.system})
      : _mode = initialMode {
    WidgetsBinding.instance.addObserver(this);
  }

  AppearanceMode _mode;

  /// The user's selected mode (which may itself be [AppearanceMode.system]).
  AppearanceMode get mode => _mode;

  bool _initialized = false;

  /// Loads the persisted mode, if any. Safe to call once; subsequent calls
  /// are no-ops. Call this right after construction, before first build if
  /// possible — a brief default-mode flash on cold start is acceptable and
  /// unavoidable for any async-persisted preference.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final stored = await AppearanceStorage.instance.load();
    if (stored != null && stored != _mode) {
      _mode = stored;
      notifyListeners();
    }
  }

  Brightness get _systemBrightness =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  /// The concrete brightness in effect right now, resolving
  /// [AppearanceMode.system] against the live platform brightness.
  Brightness get effectiveBrightness {
    switch (_mode) {
      case AppearanceMode.light:
        return Brightness.light;
      case AppearanceMode.dark:
        return Brightness.dark;
      case AppearanceMode.system:
        return _systemBrightness;
    }
  }

  /// The fully-resolved [ThemeData] (with [ReaderColors] attached) for the
  /// current [effectiveBrightness]. Widgets should not cache this — it is
  /// cheap to build and always reflects the latest mode.
  ThemeData get themeData => AppearanceThemeBuilder.build(effectiveBrightness);

  /// Convenience accessor for the reader-chrome colour tokens.
  ReaderColors get readerColors =>
      ReaderColors.forBrightness(effectiveBrightness);

  /// Selects [mode] and persists the choice. No-op if [mode] is already
  /// active.
  Future<void> setMode(AppearanceMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await AppearanceStorage.instance.save(mode);
  }

  /// Cycles Light → Dark → Follow System → Light — used by the single
  /// app-bar toggle button so no extra menu/screen is required for the
  /// common case.
  Future<void> cycleMode() async {
    const order = [
      AppearanceMode.light,
      AppearanceMode.dark,
      AppearanceMode.system,
    ];
    final next = order[(order.indexOf(_mode) + 1) % order.length];
    await setMode(next);
  }

  @override
  void didChangePlatformBrightness() {
    // Only matters when following the system — otherwise the explicit
    // choice must not be overridden by an OS-level theme change.
    if (_mode == AppearanceMode.system) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
