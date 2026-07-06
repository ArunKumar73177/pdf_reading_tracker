import 'dart:async';

import 'package:flutter/foundation.dart';

import 'reading_settings_controller.dart';

/// Drives the show/hide state of the reader chrome (app bar, bottom
/// controls, FAB) while Immersive Mode is active.
///
/// ### Design notes
///
/// - This is a **separate** [ChangeNotifier] from [ReadingSettingsController]
///   on purpose: [chromeVisible] changes on every single tap (potentially
///   many times per reading session), while [ReadingSettingsController]
///   changes only when the user opens Reading Settings (rare). Keeping
///   them separate means widgets that only care about chrome visibility
///   can listen to *only* this notifier and never rebuild when, say, the
///   appearance mode changes — and nothing here ever touches
///   `PdfViewerController` or `SfPdfViewer`.
///
/// - The auto-hide timer is a plain single-shot [Timer], created only when
///   the chrome transitions to visible and cancelled the moment it either
///   fires or the chrome is hidden again.
///
/// - Scrolling does **not** reset the auto-hide timer or reveal the
///   chrome. This matches Kindle / Apple Books / Google Play Books: chrome
///   visibility is an explicit, deliberate tap action during immersive
///   reading, not an incidental side effect of turning pages.
///
/// ### Stability-pass fix
///
/// [_onSettingsChanged] previously read `settings.value.immersiveModeEnabled`
/// and unconditionally forced chrome visibility to match it on **every**
/// `ReadingSettings` change — including changes to `keepScreenAwakeEnabled`
/// or `dndEnabled` that have nothing to do with immersive chrome. That
/// meant toggling Keep Screen Awake while mid-session (chrome currently
/// visible from a recent tap) would silently snap the chrome back to
/// hidden. This is now tracked explicitly via [_lastImmersiveModeEnabled]
/// so only a genuine change to *that specific field* affects visibility.
/// Turning Auto-hide Controls off while a hide timer is pending still
/// cancels that pending timer (so a stale timer never fires against the
/// new preference), without forcing visibility either way.
///
/// ### Priority #1/#2 audit fix — auto-hide delay
///
/// [_autoHideDelay] was previously 4 seconds. Spec calls for 3 seconds of
/// inactivity before the chrome auto-hides again. Nothing else about the
/// hide/show mechanics changes — this is a single constant.
class ImmersiveVisibilityController extends ChangeNotifier {
  ImmersiveVisibilityController({required this.settings});

  final ReadingSettingsController settings;

  static const Duration _autoHideDelay = Duration(seconds: 3);

  bool _chromeVisible = true;
  bool get chromeVisible => _chromeVisible;

  Timer? _autoHideTimer;
  bool _initialized = false;

  /// Tracks the immersive-mode flag specifically, so [_onSettingsChanged]
  /// can distinguish "immersive mode itself changed" from "some other
  /// reading setting changed while immersive mode stayed the same."
  bool _lastImmersiveModeEnabled = false;

  /// Call once after construction. Sets the initial chrome state to match
  /// whatever Immersive Mode setting was just loaded (e.g. restored from
  /// disk), and starts listening for future settings changes.
  void init() {
    if (_initialized) return;
    _initialized = true;
    _lastImmersiveModeEnabled = settings.value.immersiveModeEnabled;
    _chromeVisible = !_lastImmersiveModeEnabled;
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final immersiveNow = settings.value.immersiveModeEnabled;
    final immersiveJustChanged = immersiveNow != _lastImmersiveModeEnabled;
    _lastImmersiveModeEnabled = immersiveNow;

    if (immersiveJustChanged) {
      _autoHideTimer?.cancel();
      _autoHideTimer = null;

      if (!immersiveNow) {
        // Immersive Mode turned off — chrome must always be visible from
        // here on, exactly like the pre-Phase-3 reader.
        if (!_chromeVisible) {
          _chromeVisible = true;
          notifyListeners();
        }
        return;
      }

      // Immersive Mode was just turned on — start the session hidden.
      if (_chromeVisible) {
        _chromeVisible = false;
        notifyListeners();
      }
      return;
    }

    // Immersive Mode itself did NOT change — some unrelated reading
    // setting did (Keep Screen Awake, DND intent, etc). Chrome visibility
    // must not be touched. The one exception: if Auto-hide Controls was
    // just turned off, cancel any pending hide timer so it doesn't fire
    // against the new preference — but don't force visibility either way.
    if (!settings.value.autoHideControlsEnabled && _autoHideTimer != null) {
      _autoHideTimer?.cancel();
      _autoHideTimer = null;
    }
  }

  /// Toggles chrome visibility. No-op when Immersive Mode is off — in that
  /// state the chrome is always visible and a tap on the page has no
  /// chrome-related effect (matches the pre-Phase-3 reader exactly).
  void toggle() {
    if (!settings.value.immersiveModeEnabled) return;
    _chromeVisible = !_chromeVisible;
    if (_chromeVisible) {
      _scheduleAutoHide();
    } else {
      _autoHideTimer?.cancel();
      _autoHideTimer = null;
    }
    notifyListeners();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    if (!settings.value.autoHideControlsEnabled) {
      _autoHideTimer = null;
      return;
    }
    _autoHideTimer = Timer(_autoHideDelay, () {
      _autoHideTimer = null;
      _chromeVisible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
