/// Lightweight design tokens shared across reader-chrome widgets.
///
/// `ReaderColors` (see `theme_extensions.dart`) is the "Colors" token —
/// it's kept as a [ThemeExtension] rather than a const class here because
/// it needs brightness-aware values *and* smooth interpolation via
/// [ThemeExtension.lerp] when [AnimatedTheme] cross-fades between modes.
/// Spacing / radius / elevation / duration do not vary by brightness, so
/// plain compile-time constants are sufficient — no extra allocation, no
/// context lookup required.
library;

import 'package:flutter/material.dart';

/// Spacing scale (logical pixels). Generous by default, per the "calm,
/// distraction-free" UX requirement.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner-radius scale.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 24;
}

/// Elevation scale. Kept low/flat — Material 3's surface-tint elevation is
/// preferred over heavy shadows per the UX requirements.
abstract final class AppElevation {
  static const double none = 0;
  static const double low = 1;
  static const double medium = 3;
}

/// Animation timing tokens. All transitions in this package should use one
/// of these rather than a magic-number [Duration] literal.
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);

  /// Standard easing for reader-chrome transitions.
  static const Curve curve = Curves.easeInOut;
}

/// Small reader-specific typographic tuning that layers on top of the
/// ambient Material 3 [TextTheme] rather than replacing it. The package
/// does not define its own font sizes/weights — those come from
/// `AppearanceThemeBuilder`'s `ColorScheme`-driven [ThemeData] — this only
/// captures the handful of reading-specific values (line height, letter
/// spacing) that Material's defaults don't cover.
abstract final class AppTypography {
  static const double readingLineHeight = 1.5;
  static const double compactLineHeight = 1.2;
  static const double looseLetterSpacing = 0.1;
}
